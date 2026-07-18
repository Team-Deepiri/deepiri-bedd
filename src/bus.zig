const std = @import("std");
const config = @import("config.zig");

/// Bus client for Sugar Glider HTTP API (/health, /v1/publish, /v1/read, /v1/ack).
/// v0: doctor + publish stub helpers; full read loop lands in v1.

pub fn doctor(allocator: std.mem.Allocator, cfg: config.Config) !void {
    _ = allocator;
    const out = std.io.getStdOut().writer();
    try out.print("flint doctor\n", .{});
    try out.print("  sugar_glider_url: {s}\n", .{cfg.sugar_glider_url});
    try out.print("  sender:           {s}\n", .{cfg.sender});
    try out.print("  version:          {s}\n", .{config.version});
    try out.writeAll("  note:              HTTP probe lands in v1 (no network in CI unit path)\n");
    try out.writeAll("  status:            ok (config loaded)\n");
}

pub const PublishRequest = struct {
    stream: []const u8,
    event_type: []const u8,
    sender: []const u8,
    payload_json: []const u8,
};

/// Encode a Sugar Glider-compatible publish JSON body (no network).
pub fn encodePublishBody(allocator: std.mem.Allocator, req: PublishRequest) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.writer().print(
        \\{{"stream":"{s}","event_type":"{s}","sender":"{s}","priority":"normal","payload":{s}}}
    ,
        .{ req.stream, req.event_type, req.sender, req.payload_json },
    );
    return list.toOwnedSlice();
}

test "encodePublishBody shapes sugar glider json" {
    const body = try encodePublishBody(std.testing.allocator, .{
        .stream = "document.artifacts",
        .event_type = "document.artifacts.route",
        .sender = "flint",
        .payload_json = "{\"ok\":true}",
    });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "document.artifacts") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"sender\":\"flint\"") != null);
}
