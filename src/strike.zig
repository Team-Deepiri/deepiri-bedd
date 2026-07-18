const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");

/// One consume→execute→publish cycle. v0 is dry-run only (no WASM yet).

pub fn dryRun(
    allocator: std.mem.Allocator,
    cfg: config.Config,
    stream: []const u8,
    event_type: []const u8,
) !void {
    const payload = "{\"flint\":\"strike\",\"status\":\"dry-run\"}";
    const body = try bus.encodePublishBody(allocator, .{
        .stream = stream,
        .event_type = event_type,
        .sender = cfg.sender,
        .payload_json = payload,
    });
    defer allocator.free(body);

    const out = std.io.getStdOut().writer();
    try out.print("flint strike (dry-run)\n", .{});
    try out.print("  stream:     {s}\n", .{stream});
    try out.print("  event_type: {s}\n", .{event_type});
    try out.print("  sidecar:    {s}\n", .{cfg.sugar_glider_url});
    try out.print("  would POST {s}/v1/publish\n", .{cfg.sugar_glider_url});
    try out.print("  body:       {s}\n", .{body});
}
