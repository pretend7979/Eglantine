param(
    [string]$MsysRoot = 'C:\msys64',
    [string]$BuildDirectory,
    [string]$PackageDirectory,
    [int]$Jobs = 6,
    [switch]$PackageOnly
)

$ErrorActionPreference = 'Stop'
$sourceDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (!$BuildDirectory) { $BuildDirectory = Join-Path $sourceDirectory 'build/local-release' }
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
if (!$PackageDirectory) { $PackageDirectory = Join-Path $BuildDirectory 'package' }
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
$toolchain = Join-Path $MsysRoot 'clang64'
$toolsBin = Join-Path $toolchain 'bin'
$env:PATH = "$toolsBin;$(Join-Path $MsysRoot 'usr/bin');$env:PATH"
$cmake = Join-Path $toolsBin 'cmake.exe'

if (!$PackageOnly) {
    & $cmake -S $sourceDirectory -B $BuildDirectory -G Ninja `
        "-DCMAKE_C_COMPILER=$toolsBin/clang.exe" `
        "-DCMAKE_CXX_COMPILER=$toolsBin/clang++.exe" `
        -DCMAKE_BUILD_TYPE=Release -DENABLE_QT=ON -DYUZU_USE_BUNDLED_QT=OFF `
        "-DQt6_DIR=$toolchain/lib/cmake/Qt6" `
        -DYUZU_CMD=ON -DYUZU_ROOM=OFF -DYUZU_ROOM_STANDALONE=OFF `
        -DYUZU_TESTS=OFF -DYUZU_USE_BUNDLED_SDL3=ON -DENABLE_UPDATE_CHECKER=OFF `
        -DUSE_DISCORD_PRESENCE=OFF -DENABLE_LIBUSB=OFF `
        -DVulkanHeaders_FORCE_BUNDLED=ON -DVulkanUtilityLibraries_FORCE_BUNDLED=ON `
        -Denet_FORCE_BUNDLED=ON
    if ($LASTEXITCODE) { throw 'CMake configuration failed' }
    & $cmake --build $BuildDirectory --target yuzu yuzu-cmd -j $Jobs
    if ($LASTEXITCODE) { throw 'Release build failed' }
}

New-Item -ItemType Directory -Force -Path $PackageDirectory | Out-Null
foreach ($name in @('eglantine.exe', 'eden-cli.exe')) {
    Copy-Item -LiteralPath (Join-Path $BuildDirectory "bin/$name") -Destination $PackageDirectory -Force
}
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'dist/nx2_switches.txt') -Destination $PackageDirectory -Force
$deploy = Join-Path $toolsBin 'windeployqt6.exe'
& $deploy --release --no-translations --no-compiler-runtime --no-opengl-sw `
    --no-system-d3d-compiler --no-system-dxc-compiler `
    --dir $PackageDirectory (Join-Path $PackageDirectory 'eglantine.exe')
if ($LASTEXITCODE) { throw 'Qt deployment failed' }

# Include all non-system imports, including the imports of Qt plugins and FFmpeg codecs.
$pending = [Collections.Generic.Queue[string]]::new()
Get-ChildItem -LiteralPath $PackageDirectory -Recurse -File |
    Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object { $pending.Enqueue($_.FullName) }
$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$objdump = Join-Path $toolsBin 'llvm-objdump.exe'
while ($pending.Count) {
    $binary = $pending.Dequeue()
    if (!$visited.Add($binary)) { continue }
    $imports = & $objdump -p $binary
    if ($LASTEXITCODE) { throw "Cannot inspect imports: $binary" }
    foreach ($line in $imports) {
        if ($line -cnotmatch '^\s+DLL Name: (.+)$') { continue }
        $name = $Matches[1].Trim()
        if ($name -match '^(api|ext)-ms-' -or
            (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32/$name"))) { continue }
        $destination = Join-Path $PackageDirectory $name
        if (!(Test-Path -LiteralPath $destination)) {
            $dependency = Join-Path $toolsBin $name
            if (!(Test-Path -LiteralPath $dependency)) { throw "Missing dependency $name for $binary" }
            Copy-Item -LiteralPath $dependency -Destination $destination
        }
        $pending.Enqueue($destination)
    }
}
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'LICENSE.txt') -Destination $PackageDirectory -Force
Copy-Item -LiteralPath (Join-Path $sourceDirectory 'LICENSES') -Destination $PackageDirectory -Recurse -Force
$runtimeLicenses = Join-Path $PackageDirectory 'runtime-licenses'
New-Item -ItemType Directory -Force -Path $runtimeLicenses | Out-Null
Get-ChildItem -LiteralPath (Join-Path $toolchain 'share/licenses') |
    Copy-Item -Destination $runtimeLicenses -Recurse -Force
Write-Host "Release package: $PackageDirectory"
