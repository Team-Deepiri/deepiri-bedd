const std = @import("std");

pub const version = "0.1.0";

pub const Config = struct {
    sugar_glider_url: []const u8,
    sender: []const u8,
    owned_url: bool,
    owned_sender: bool,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        if (self.owned_url) allocator.free(self.sugar_glider_url);
        if (self.owned_sender) allocator.free(self.sender);
    }
};

pub fn loadFromEnv(allocator: std.mem.Allocator) !Config {
    const url = blk: {
        if (std.posix.getenv("FLINT_SUGAR_GLIDER_URL")) |v| break :blk .{ v, false };
        if (std.posix.getenv("SYNAPSE_SUGAR_GLIDER_URL")) |v| break :blk .{ v, false };
        if (std.posix.getenv("SYNAPSE_SIDECAR_URL")) |v| break :blk .{ v, false };
        break :blk .{ try allocator.dupe(u8, "http://127.0.0.1:8081"), true };
    };

    const sender = blk: {
        if (std.posix.getenv("FLINT_SENDER")) |v| break :blk .{ v, false };
        break :blk .{ try allocator.dupe(u8, "flint"), true };
    };

    return .{
        .sugar_glider_url = stripTrailingSlash(url[0]),
        .sender = sender[0],
        .owned_url = url[1],
        .owned_sender = sender[1],
    };
}

fn stripTrailingSlash(url: []const u8) []const u8 {
    if (url.len > 0 and url[url.len - 1] == '/') {
        return url[0 .. url.len - 1];
    }
    return url;
}
