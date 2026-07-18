const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const ember_mod = @import("ember.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const tinder_mod = @import("tinder.zig");

pub fn run(allocator: std.mem.Allocator, cfg: *config.Config) !void {
    var tinder = try tinder_mod.loadOrDefault(allocator, cfg.tinder_path);
    defer tinder.deinit();

    var registry = skill.Registry.init(allocator, cfg.skills_dir);
    defer registry.deinit();

    var metrics = ember_mod.Ember{};
    var client = bus.Client.init(allocator, cfg.*);
    defer client.deinit();

    const streams = try tinder.uniqueStreams(allocator);
    defer allocator.free(streams);

    const out = std.io.getStdOut().writer();
    try out.print("flint serve\n", .{});
    try out.print("  sidecar: {s}\n", .{cfg.sugar_glider_url});
    try out.print("  group:   {s}\n", .{cfg.consumer_group});
    try out.print("  name:    {s}\n", .{cfg.consumer_name});
    try out.print("  dry_run: {}\n", .{cfg.dry_run});
    try out.print("  streams: {d}\n", .{streams.len});
    for (streams) |s| try out.print("    - {s}\n", .{s});
    try out.writeAll("  skills:\n");
    try skill.Registry.listBuiltins(out);

    var consecutive_failures: u32 = 0;
    while (true) {
        var progressed = false;
        for (streams) |stream| {
            const events = client.read(.{
                .stream = stream,
                .consumer_group = cfg.consumer_group,
                .consumer_name = cfg.consumer_name,
                .count = cfg.read_count,
                .block_ms = cfg.block_ms,
            }) catch |err| {
                consecutive_failures += 1;
                std.log.warn("read {s} failed: {s} (failures={d})", .{
                    stream,
                    @errorName(err),
                    consecutive_failures,
                });
                if (consecutive_failures > 30) {
                    std.time.sleep(2 * std.time.ns_per_s);
                }
                continue;
            };
            defer {
                for (events) |e| e.deinit(allocator);
                allocator.free(events);
            }

            consecutive_failures = 0;
            metrics.reads += 1;

            if (events.len == 0) continue;
            progressed = true;

            var ack_ids = std.ArrayList([]const u8).init(allocator);
            defer ack_ids.deinit();

            for (events) |event| {
                const route = tinder.match(event.stream, event.event_type) orelse {
                    std.log.warn("no route for {s} event={s}; acking", .{ event.stream, event.event_type });
                    try ack_ids.append(event.entry_id);
                    continue;
                };

                strike.executeOne(allocator, cfg, &client, &registry, &metrics, route, event) catch {
                    // Leave unacked for retry
                    continue;
                };
                try ack_ids.append(event.entry_id);
            }

            if (ack_ids.items.len > 0 and !cfg.dry_run) {
                const n = client.ack(stream, cfg.consumer_group, ack_ids.items) catch |err| {
                    std.log.err("ack failed: {s}", .{@errorName(err)});
                    continue;
                };
                metrics.acks += @intCast(n);
            } else if (ack_ids.items.len > 0 and cfg.dry_run) {
                metrics.acks += @intCast(ack_ids.items.len);
            }
        }

        if (!progressed) {
            // brief pause when idle across all streams (block_ms already waited per read)
            std.time.sleep(50 * std.time.ns_per_ms);
        }

        // Periodic ember dump every ~100 reads
        if (metrics.reads > 0 and metrics.reads % 50 == 0) {
            try metrics.print(std.io.getStdErr().writer());
        }
    }
}
