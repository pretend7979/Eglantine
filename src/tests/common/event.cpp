// SPDX-License-Identifier: GPL-3.0-or-later

#include <atomic>
#include <chrono>
#include <thread>

#include <catch2/catch_test_macros.hpp>
#include "common/thread.h"

using namespace std::chrono_literals;

TEST_CASE("Event timed waits consume one pending signal", "[common][event]") {
    Common::Event event;
    REQUIRE_FALSE(event.WaitFor(0ns));
    REQUIRE_FALSE(event.WaitFor(-1ns));
    event.Set();
    event.Set();
    REQUIRE(event.WaitFor(0ns));
    REQUIRE_FALSE(event.WaitFor(0ns));
    event.Set();
    event.Reset();
    REQUIRE_FALSE(event.WaitFor(0ns));
}

TEST_CASE("Event timeout does not return early", "[common][event]") {
    Common::Event event;
    const auto start = std::chrono::steady_clock::now();
    REQUIRE_FALSE(event.WaitFor(20ms));
    REQUIRE(std::chrono::steady_clock::now() - start >= 20ms);
}

TEST_CASE("Event signals wake timed waiters", "[common][event]") {
    Common::Event event;
    Common::Event ready;
    std::jthread producer([&] {
        ready.Wait();
        event.Set();
    });
    ready.Set();
    REQUIRE(event.WaitFor(2s));
    REQUIRE_FALSE(event.WaitFor(0ns));
}

TEST_CASE("Event signal is consumed by only one waiter", "[common][event]") {
    Common::Event event;
    std::atomic<unsigned> signaled{};
    const auto wait = [&] {
        if (event.WaitFor(100ms)) {
            ++signaled;
        }
    };
    std::jthread first(wait);
    std::jthread second(wait);
    event.Set();
    first.join();
    second.join();
    REQUIRE(signaled.load() == 1);
    REQUIRE_FALSE(event.IsSet());
}
