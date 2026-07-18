const std = @import("std");

pub fn nowIso8601(buf: []u8) ![]const u8 {
    const ts = std.time.timestamp();
    return std.fmt.bufPrint(buf, "{d}", .{ts});
}

pub fn msSince(start_ns: i128) u64 {
    const elapsed = std.time.nanoTimestamp() - start_ns;
    if (elapsed <= 0) return 0;
    return @intCast(@divTrunc(elapsed, std.time.ns_per_ms));
}

test "msSince non-negative" {
    const t = std.time.nanoTimestamp();
    try std.testing.expect(msSince(t) >= 0);
}
