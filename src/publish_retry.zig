const std = @import("std");
const bus = @import("bus.zig");
const backoff = @import("util/backoff.zig");

pub const CircuitState = enum { closed, open, half_open };

pub const CircuitBreaker = struct {
    failures: u32 = 0,
    threshold: u32 = 5,
    open_until_ms: i64 = 0,
    cooldown_ms: i64 = 5000,
    state: CircuitState = .closed,

    pub fn allow(self: *CircuitBreaker) bool {
        if (self.state == .open) {
            const now = std.time.milliTimestamp();
            if (now >= self.open_until_ms) {
                self.state = .half_open;
                return true;
            }
            return false;
        }
        return true;
    }

    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.failures = 0;
        self.state = .closed;
    }

    pub fn recordFailure(self: *CircuitBreaker) void {
        self.failures += 1;
        if (self.failures >= self.threshold) {
            self.state = .open;
            self.open_until_ms = std.time.milliTimestamp() + self.cooldown_ms;
        }
    }
};

pub fn publishWithRetry(
    client: *bus.Client,
    req: bus.PublishRequest,
    breaker: *CircuitBreaker,
    max_attempts: u32,
) !bus.PublishResult {
    if (!breaker.allow()) return error.CircuitOpen;

    var attempt: u32 = 0;
    var last_err: anyerror = error.HttpFailed;
    while (attempt < max_attempts) : (attempt += 1) {
        const result = client.publish(req) catch |err| {
            last_err = err;
            breaker.recordFailure();
            const ms = backoff.exponential(attempt, 25, 2000);
            std.time.sleep(ms * std.time.ns_per_ms);
            continue;
        };
        breaker.recordSuccess();
        return result;
    }
    return last_err;
}

test "circuit opens after threshold" {
    var cb = CircuitBreaker{ .threshold = 3, .cooldown_ms = 10_000 };
    try std.testing.expect(cb.allow());
    cb.recordFailure();
    cb.recordFailure();
    cb.recordFailure();
    try std.testing.expect(!cb.allow());
    try std.testing.expect(cb.state == .open);
}
