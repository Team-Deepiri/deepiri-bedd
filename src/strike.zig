const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const ember = @import("ember.zig");
const jsonx = @import("jsonx.zig");
const skill = @import("skill/mod.zig");
const tinder = @import("tinder.zig");
const publish_retry = @import("publish_retry.zig");

pub fn dryRun(
    allocator: std.mem.Allocator,
    cfg: config.Config,
    stream: []const u8,
    event_type: []const u8,
    skill_name: []const u8,
) !void {
    var reg = skill.Registry.init(allocator, cfg.skills_dir);
    defer reg.deinit();

    const input =
        \\{"bedd":"strike","status":"dry-run"}
    ;
    const ctx = skill.SkillContext{
        .allocator = allocator,
        .stream = stream,
        .entry_id = "dry-run",
        .event_type = event_type,
    };
    const result = try reg.run(skill_name, ctx, input);
    defer result.deinit(allocator);

    const wrapped = try jsonx.wrapStrikeResult(allocator, skill_name, stream, "dry-run", result.payload_json);
    defer allocator.free(wrapped);

    const body = try bus.encodePublishBody(allocator, .{
        .stream = "inference-events",
        .event_type = "bedd.strike.result",
        .sender = cfg.sender,
        .payload_json = wrapped,
    });
    defer allocator.free(body);

    const out = std.io.getStdOut().writer();
    try out.print("bedd strike (dry-run)\n", .{});
    try out.print("  stream:     {s}\n", .{stream});
    try out.print("  event_type: {s}\n", .{event_type});
    try out.print("  skill:      {s}\n", .{skill_name});
    try out.print("  sidecar:    {s}\n", .{cfg.bus_url});
    try out.print("  result:     {s}\n", .{result.payload_json});
    try out.print("  would POST {s}/v1/publish\n", .{cfg.bus_url});
    try out.print("  body:       {s}\n", .{body});
}

pub fn executeOne(
    allocator: std.mem.Allocator,
    cfg: *const config.Config,
    client: *bus.Client,
    registry: *skill.Registry,
    metrics: *ember.Ember,
    breaker: *publish_retry.CircuitBreaker,
    route: tinder.Route,
    event: bus.StreamEvent,
) !void {
    const started_ns = std.time.nanoTimestamp();

    const result = runSkillChain(allocator, registry, route.skill, event) catch |err| {
        // Recovery skill (optional) before surfacing failure to caller/DLQ.
        if (route.recovery_skill.len > 0) {
            std.log.warn("skill chain failed; trying recovery_skill={s}", .{route.recovery_skill});
            const recovered = runSkillChain(allocator, registry, route.recovery_skill, event) catch {
                metrics.record(event.stream, route.skill, false, 0);
                return err;
            };
            defer recovered.deinit(allocator);
            try publishResult(allocator, cfg, client, metrics, breaker, route, event, recovered.payload_json, started_ns);
            return;
        }
        metrics.record(event.stream, route.skill, false, 0);
        return err;
    };
    defer result.deinit(allocator);

    try publishResult(allocator, cfg, client, metrics, breaker, route, event, result.payload_json, started_ns);
}

fn runSkillChain(
    allocator: std.mem.Allocator,
    registry: *skill.Registry,
    skill_spec: []const u8,
    event: bus.StreamEvent,
) !skill.SkillResult {
    var current = try allocator.dupe(u8, event.payload_json);
    errdefer allocator.free(current);

    var it = std.mem.splitScalar(u8, skill_spec, ',');
    var ran_any = false;

    while (it.next()) |part| {
        const name = std.mem.trim(u8, part, " \t");
        if (name.len == 0) continue;
        ran_any = true;
        const ctx = skill.SkillContext{
            .allocator = allocator,
            .stream = event.stream,
            .entry_id = event.entry_id,
            .event_type = event.event_type,
        };
        const next = try registry.run(name, ctx, current);
        allocator.free(current);
        current = next.payload_json;
        if (next.event_type_override) |e| allocator.free(e);
    }

    if (!ran_any) {
        allocator.free(current);
        return skill.SkillError.SkillNotFound;
    }

    return .{ .payload_json = current };
}

fn publishResult(
    allocator: std.mem.Allocator,
    cfg: *const config.Config,
    client: *bus.Client,
    metrics: *ember.Ember,
    breaker: *publish_retry.CircuitBreaker,
    route: tinder.Route,
    event: bus.StreamEvent,
    payload_json: []const u8,
    started_ns: i128,
) !void {
    const lean = cfg.lean;
    const to_publish = if (lean)
        try allocator.dupe(u8, payload_json)
    else
        try jsonx.wrapStrikeResult(allocator, route.skill, event.stream, event.entry_id, payload_json);
    defer allocator.free(to_publish);

    const pub_event = route.publish_event_type;

    if (cfg.dry_run) {
        std.log.info("dry-run publish stream={s} event={s} payload_len={d}", .{
            route.publish_stream,
            pub_event,
            to_publish.len,
        });
    } else {
        const pub_res = try publish_retry.publishWithRetry(client, .{
            .stream = route.publish_stream,
            .event_type = pub_event,
            .sender = cfg.sender,
            .payload_json = to_publish,
        }, breaker, 4);
        defer pub_res.deinit(allocator);
        metrics.publishes += 1;
        std.log.info("published entry_id={s} stream={s}", .{ pub_res.entry_id, route.publish_stream });

        // Publisher confirm: optional confirm stream after successful publish.
        if (route.confirm and cfg.confirms and cfg.confirm_stream.len > 0) {
            const conf = try std.fmt.allocPrint(
                allocator,
                \\{{"confirmed":true,"source_stream":"{s}","source_entry":"{s}","publish_stream":"{s}","publish_entry":"{s}"}}
            ,
                .{ event.stream, event.entry_id, route.publish_stream, pub_res.entry_id },
            );
            defer allocator.free(conf);
            const c_res = client.publish(.{
                .stream = cfg.confirm_stream,
                .event_type = "bedd.confirm",
                .sender = cfg.sender,
                .payload_json = conf,
            }) catch null;
            if (c_res) |cr| cr.deinit(allocator);
        }
    }

    const elapsed = std.time.nanoTimestamp() - started_ns;
    const ms: u64 = if (elapsed > 0) @intCast(@divTrunc(elapsed, std.time.ns_per_ms)) else 0;
    metrics.record(event.stream, route.skill, true, ms);
}
