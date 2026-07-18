//! Test root — re-exports modules under test.
pub const bus = @import("bus.zig");
pub const config = @import("config.zig");
pub const tinder = @import("tinder.zig");
pub const ember = @import("ember.zig");
pub const strike = @import("strike.zig");
pub const skill = @import("skill/mod.zig");
pub const jsonx = @import("jsonx.zig");
pub const topics = @import("topics.zig");

test {
    _ = bus;
    _ = config;
    _ = tinder;
    _ = ember;
    _ = strike;
    _ = skill;
    _ = jsonx;
    _ = topics;
}
