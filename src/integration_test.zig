const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const mock_sidecar = @import("mock_sidecar.zig");
const skill = @import("skill/mod.zig");
const strike = @import("strike.zig");
const ember = @import("ember.zig");
const tinder = @import("tinder.zig");
const publish_retry = @import("publish_retry.zig");

test "end-to-end strike against mock sugar glider" {
    var mock = mock_sidecar.MockSidecar.init(std.testing.allocator, 19118);
    try mock.start();
    defer mock.deinit();
    std.time.sleep(50 * std.time.ns_per_ms);

    try mock.seed(
        "document.artifacts",
        "document.artifacts.route",
        \\{"documentId":"doc-e2e","artifactType":"document.extraction"}
    ,
    );

    var cfg = try config.loadFromEnv(std.testing.allocator);
    defer cfg.deinit();
    // Point at mock
    std.testing.allocator.free(cfg.sugar_glider_url);
    cfg.sugar_glider_url = try std.testing.allocator.dupe(u8, "http://127.0.0.1:19118");
    cfg.dry_run = false;

    var client = bus.Client.init(std.testing.allocator, cfg);
    defer client.deinit();

    try std.testing.expect(try client.health());

    const events = try client.read(.{
        .stream = "document.artifacts",
        .consumer_group = "flint-test",
        .consumer_name = "t1",
        .count = 10,
        .block_ms = 100,
    });
    defer {
        for (events) |e| e.deinit(std.testing.allocator);
        std.testing.allocator.free(events);
    }
    try std.testing.expect(events.len >= 1);

    var reg = skill.Registry.init(std.testing.allocator, ".");
    defer reg.deinit();
    var metrics = ember.Ember{};
    var breaker = publish_retry.CircuitBreaker{};

    const route = tinder.Route{
        .stream = "document.artifacts",
        .event_type = "*",
        .skill = "artifact_claim",
        .publish_stream = "inference-events",
        .publish_event_type = "flint.artifact.claimed",
    };

    try strike.executeOne(
        std.testing.allocator,
        &cfg,
        &client,
        &reg,
        &metrics,
        &breaker,
        route,
        events[0],
    );
    try std.testing.expectEqual(@as(u64, 1), metrics.strikes_ok);
    try std.testing.expectEqual(@as(u64, 1), metrics.publishes);

    _ = try client.ack("document.artifacts", "flint-test", &.{events[0].entry_id});
    try std.testing.expect(mock.acked >= 1);
}
