//! Dead-letter queue inspection and replay.
//!
//! `bus_dlq.publishDeadLetter` writes a `bedd.dlq.v1` envelope carrying enough
//! context to put a failed event back where it came from:
//!
//!   {"schemaVersion":"bedd.dlq.v1","source_stream":"…","entry_id":"…",
//!    "error":"…","payload":{…}}
//!
//! These subcommands are the read side of that: see what is stuck, and replay it.
//! All of them scan with XRANGE rather than XREADGROUP, so inspecting the DLQ
//! never creates pending entries or competes with a running `serve`.

const std = @import("std");
const bus = @import("bus.zig");
const bus_redis = @import("bus_redis.zig");
const config = @import("config.zig");
const jsonx = @import("jsonx.zig");

/// How many entries a single scan pulls when no --limit is given. High enough to
/// cover a realistic backlog, bounded so a runaway DLQ can't exhaust memory.
pub const default_scan_limit: i64 = 1000;

pub const Options = struct {
    /// Only act on entries whose `error` contains this substring.
    error_filter: ?[]const u8 = null,
    /// Only act on entries from this source stream.
    source_filter: ?[]const u8 = null,
    limit: i64 = default_scan_limit,
    json: bool = false,
    /// replay: report what would happen, change nothing.
    dry_run: bool = false,
    /// replay: publish here instead of each entry's own source_stream.
    to_stream: ?[]const u8 = null,
    /// replay: leave entries in the DLQ after a successful republish.
    keep: bool = false,
};

/// One decoded `bedd.dlq.v1` envelope, borrowed from the owning StreamEvent.
pub const Entry = struct {
    /// Entry id in the DLQ stream, used to delete it after replay.
    dlq_entry_id: []const u8,
    source_stream: []const u8,
    /// Entry id the event had in its source stream, for tracing.
    origin_entry_id: []const u8,
    /// Event type before the failure. Empty for entries written before the
    /// envelope carried it — replay falls back to the DLQ event's own type.
    source_event_type: []const u8,
    error_name: []const u8,
    payload_json: []const u8,

    /// Millisecond timestamp encoded in the Redis entry id (`<ms>-<seq>`).
    pub fn timestampMs(self: Entry) ?i64 {
        const dash = std.mem.indexOfScalar(u8, self.dlq_entry_id, '-') orelse return null;
        return std.fmt.parseInt(i64, self.dlq_entry_id[0..dash], 10) catch null;
    }
};

/// Decode an envelope. Entries that predate the envelope, or come from another
/// producer, still yield an Entry — with "unknown" fields and the raw payload —
/// so a malformed record is visible rather than silently skipped.
pub fn decode(event: bus.StreamEvent) Entry {
    const body = event.payload_json;
    return .{
        .dlq_entry_id = event.entry_id,
        .source_stream = jsonx.getStringField(body, "source_stream") orelse "unknown",
        .origin_entry_id = jsonx.getStringField(body, "entry_id") orelse "unknown",
        .source_event_type = jsonx.getStringField(body, "source_event_type") orelse "",
        .error_name = jsonx.getStringField(body, "error") orelse "unknown",
        .payload_json = extractPayload(body),
    };
}

/// These subcommands need XRANGE/XDEL, which only the direct Redis transport
/// has. Fail here with something actionable rather than letting an
/// UnsupportedTransport error reach the user with no context.
pub fn requireRedis(cfg: config.Config) void {
    if (bus_redis.isRedisUrl(cfg.bus_url)) return;
    std.io.getStdErr().writer().print(
        "bedd dlq needs a direct Redis bus, but BEDD_BUS_URL is '{s}'.\n" ++
            "Set BEDD_BUS_URL=redis://host:port[/db] and retry.\n",
        .{cfg.bus_url},
    ) catch {};
    std.process.exit(2);
}

fn matches(entry: Entry, opts: Options) bool {
    if (opts.error_filter) |f| {
        if (std.mem.indexOf(u8, entry.error_name, f) == null) return false;
    }
    if (opts.source_filter) |f| {
        if (!std.mem.eql(u8, entry.source_stream, f)) return false;
    }
    return true;
}

const Scan = struct {
    events: []bus.StreamEvent,
    allocator: std.mem.Allocator,

    fn deinit(self: Scan) void {
        for (self.events) |e| e.deinit(self.allocator);
        self.allocator.free(self.events);
    }
};

fn scan(allocator: std.mem.Allocator, client: *bus.Client, stream: []const u8, limit: i64) !Scan {
    const events = try client.range(stream, "-", "+", limit);
    return .{ .events = events, .allocator = allocator };
}

// ---------------------------------------------------------------------------
// stats
// ---------------------------------------------------------------------------

/// Counts by error and by source stream, plus the age of the oldest entry —
/// enough to answer "is anything stuck, and since when" without paging through
/// the whole queue.
pub fn stats(allocator: std.mem.Allocator, cfg: config.Config, opts: Options) !void {
    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();

    const total = try client.streamLen(cfg.dlq_stream);

    const s = try scan(allocator, &client, cfg.dlq_stream, opts.limit);
    defer s.deinit();

    var by_error = std.StringArrayHashMap(u32).init(allocator);
    defer by_error.deinit();
    var by_source = std.StringArrayHashMap(u32).init(allocator);
    defer by_source.deinit();

    var oldest: ?i64 = null;
    var newest: ?i64 = null;
    var counted: u32 = 0;

    for (s.events) |event| {
        const entry = decode(event);
        if (!matches(entry, opts)) continue;
        counted += 1;

        (try by_error.getOrPutValue(entry.error_name, 0)).value_ptr.* += 1;
        (try by_source.getOrPutValue(entry.source_stream, 0)).value_ptr.* += 1;

        if (entry.timestampMs()) |ts| {
            if (oldest == null or ts < oldest.?) oldest = ts;
            if (newest == null or ts > newest.?) newest = ts;
        }
    }

    const out = std.io.getStdOut().writer();
    const now = std.time.milliTimestamp();

    if (opts.json) {
        try out.print("{{\"stream\":\"{s}\",\"total\":{d},\"scanned\":{d}", .{ cfg.dlq_stream, total, counted });
        if (oldest) |o| try out.print(",\"oldest_age_seconds\":{d}", .{@divTrunc(now - o, 1000)});
        try out.writeAll(",\"by_error\":{");
        try writeJsonCounts(out, by_error);
        try out.writeAll("},\"by_source_stream\":{");
        try writeJsonCounts(out, by_source);
        try out.writeAll("}}\n");
        return;
    }

    try out.print("dlq stats — {s}\n", .{cfg.dlq_stream});
    try out.print("  entries:   {d}\n", .{total});
    if (total > counted and opts.error_filter == null and opts.source_filter == null) {
        try out.print("  scanned:   {d} (--limit; raise it to see the rest)\n", .{counted});
    } else if (opts.error_filter != null or opts.source_filter != null) {
        try out.print("  matched:   {d}\n", .{counted});
    }

    if (counted == 0) {
        try out.writeAll("  nothing stuck\n");
        return;
    }

    if (oldest) |o| {
        try out.print("  oldest:    {d}s ago\n", .{@divTrunc(now - o, 1000)});
    }
    if (newest) |n| {
        try out.print("  newest:    {d}s ago\n", .{@divTrunc(now - n, 1000)});
    }

    try out.writeAll("  by error:\n");
    try writeCounts(out, by_error);
    try out.writeAll("  by source stream:\n");
    try writeCounts(out, by_source);
}

fn writeCounts(out: anytype, map: std.StringArrayHashMap(u32)) !void {
    var it = map.iterator();
    while (it.next()) |kv| {
        try out.print("    {d:>6}  {s}\n", .{ kv.value_ptr.*, kv.key_ptr.* });
    }
}

fn writeJsonCounts(out: anytype, map: std.StringArrayHashMap(u32)) !void {
    var it = map.iterator();
    var first = true;
    while (it.next()) |kv| {
        if (!first) try out.writeAll(",");
        first = false;
        try out.print("\"{s}\":{d}", .{ kv.key_ptr.*, kv.value_ptr.* });
    }
}

// ---------------------------------------------------------------------------
// list
// ---------------------------------------------------------------------------

/// One line per entry. `--json` emits NDJSON so it pipes into `bedd filter`,
/// `jq`, or anything else that reads a stream of objects.
pub fn list(allocator: std.mem.Allocator, cfg: config.Config, opts: Options) !void {
    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();

    const s = try scan(allocator, &client, cfg.dlq_stream, opts.limit);
    defer s.deinit();

    const out = std.io.getStdOut().writer();
    var shown: u32 = 0;

    for (s.events) |event| {
        const entry = decode(event);
        if (!matches(entry, opts)) continue;
        shown += 1;

        if (opts.json) {
            try out.print(
                "{{\"dlq_entry_id\":\"{s}\",\"source_stream\":\"{s}\",\"entry_id\":\"{s}\",\"source_event_type\":\"{s}\",\"error\":\"{s}\",\"payload\":{s}}}\n",
                .{ entry.dlq_entry_id, entry.source_stream, entry.origin_entry_id, entry.source_event_type, entry.error_name, entry.payload_json },
            );
        } else {
            try out.print("{s}  {s: <20}  {s: <24}  {s}\n", .{
                entry.dlq_entry_id,
                entry.source_stream,
                entry.error_name,
                firstLine(entry.payload_json, 80),
            });
        }
    }

    if (!opts.json and shown == 0) {
        try out.print("no entries in {s}\n", .{cfg.dlq_stream});
    }
}

/// Truncate a payload for single-line display, without splitting mid-line.
fn firstLine(s: []const u8, max: usize) []const u8 {
    const end = std.mem.indexOfScalar(u8, s, '\n') orelse s.len;
    return s[0..@min(end, max)];
}

// ---------------------------------------------------------------------------
// replay
// ---------------------------------------------------------------------------

pub const ReplayReport = struct {
    matched: u32 = 0,
    republished: u32 = 0,
    removed: u32 = 0,
    failed: u32 = 0,
};

/// Republish each matching entry to its source stream, then remove it from the
/// DLQ.
///
/// Order matters: publish first, delete second. A crash between the two replays
/// an event twice, which at-least-once consumers already handle; deleting first
/// would lose it outright.
pub fn replay(allocator: std.mem.Allocator, cfg: config.Config, opts: Options) !ReplayReport {
    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();

    const s = try scan(allocator, &client, cfg.dlq_stream, opts.limit);
    defer s.deinit();

    const out = std.io.getStdOut().writer();
    var report = ReplayReport{};

    var done_ids = std.ArrayList([]const u8).init(allocator);
    defer done_ids.deinit();

    for (s.events) |event| {
        const entry = decode(event);
        if (!matches(entry, opts)) continue;
        report.matched += 1;

        const target = opts.to_stream orelse entry.source_stream;
        if (std.mem.eql(u8, target, "unknown")) {
            try out.print("skip  {s}  no source_stream in envelope\n", .{entry.dlq_entry_id});
            report.failed += 1;
            continue;
        }

        if (opts.dry_run) {
            try out.print("would replay  {s}  -> {s}  ({s})\n", .{ entry.dlq_entry_id, target, entry.error_name });
            continue;
        }

        // Restore the pre-failure event type so tinder routes it the same way it
        // was routed originally. Older entries have none — those keep the DLQ
        // event's type, which is the best we can recover.
        const event_type = if (entry.source_event_type.len > 0)
            entry.source_event_type
        else
            event.event_type;

        const res = client.publish(.{
            .stream = target,
            .event_type = event_type,
            .sender = cfg.sender,
            .payload_json = entry.payload_json,
        }) catch |err| {
            try out.print("fail  {s}  -> {s}  {s}\n", .{ entry.dlq_entry_id, target, @errorName(err) });
            report.failed += 1;
            continue;
        };
        defer res.deinit(allocator);

        report.republished += 1;
        try out.print("replayed  {s}  -> {s}  {s}\n", .{ entry.dlq_entry_id, target, res.entry_id });

        if (!opts.keep) try done_ids.append(entry.dlq_entry_id);
    }

    if (done_ids.items.len > 0) {
        const removed = client.del(cfg.dlq_stream, done_ids.items) catch |err| blk: {
            try out.print("warn  republished but could not remove from dlq: {s}\n", .{@errorName(err)});
            break :blk 0;
        };
        report.removed = @intCast(@max(removed, 0));
    }

    try out.print(
        "matched={d} republished={d} removed={d} failed={d}{s}\n",
        .{ report.matched, report.republished, report.removed, report.failed, if (opts.dry_run) " (dry run)" else "" },
    );
    return report;
}

// ---------------------------------------------------------------------------
// purge
// ---------------------------------------------------------------------------

/// Delete matching entries without replaying them, for records that will never
/// succeed. Requires an explicit filter unless --dry-run: an unfiltered purge is
/// almost always a mistake.
pub fn purge(allocator: std.mem.Allocator, cfg: config.Config, opts: Options) !u32 {
    const out = std.io.getStdOut().writer();

    if (opts.error_filter == null and opts.source_filter == null and !opts.dry_run) {
        try std.io.getStdErr().writer().writeAll(
            "refusing to purge the whole dlq — pass --error or --source, or --dry-run to preview\n",
        );
        std.process.exit(2);
    }

    var client = bus.Client.init(allocator, cfg);
    defer client.deinit();

    const s = try scan(allocator, &client, cfg.dlq_stream, opts.limit);
    defer s.deinit();

    var ids = std.ArrayList([]const u8).init(allocator);
    defer ids.deinit();

    for (s.events) |event| {
        const entry = decode(event);
        if (!matches(entry, opts)) continue;
        if (opts.dry_run) {
            try out.print("would purge  {s}  {s}  ({s})\n", .{ entry.dlq_entry_id, entry.source_stream, entry.error_name });
        }
        try ids.append(entry.dlq_entry_id);
    }

    if (opts.dry_run) {
        try out.print("would purge {d} entries (dry run)\n", .{ids.items.len});
        return @intCast(ids.items.len);
    }

    const removed = try client.del(cfg.dlq_stream, ids.items);
    try out.print("purged {d} entries\n", .{removed});
    return @intCast(@max(removed, 0));
}

// ---------------------------------------------------------------------------
// envelope decoding
// ---------------------------------------------------------------------------

/// Return the `payload` value as raw JSON. `jsonx.getStringField` only handles
/// string values, and the payload is an object, so find and balance it here.
fn extractPayload(body: []const u8) []const u8 {
    const key = "\"payload\"";
    const idx = std.mem.indexOf(u8, body, key) orelse return body;
    var i = idx + key.len;
    while (i < body.len and (body[i] == ' ' or body[i] == ':' or body[i] == '\t')) : (i += 1) {}
    if (i >= body.len) return body;

    if (body[i] != '{' and body[i] != '[') {
        // Scalar or string payload — hand back the literal so nothing is lost.
        const start = i;
        while (i < body.len and body[i] != ',' and body[i] != '}') : (i += 1) {}
        return std.mem.trim(u8, body[start..i], " \t");
    }

    const open = body[i];
    const close: u8 = if (open == '{') '}' else ']';
    const start = i;
    var depth: i32 = 0;
    var in_str = false;
    var escape = false;
    while (i < body.len) : (i += 1) {
        const c = body[i];
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\' and in_str) {
            escape = true;
            continue;
        }
        if (c == '"') {
            in_str = !in_str;
            continue;
        }
        if (in_str) continue;
        if (c == open) depth += 1;
        if (c == close) {
            depth -= 1;
            if (depth == 0) return body[start .. i + 1];
        }
    }
    return body[start..];
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

fn testEvent(payload: []const u8) bus.StreamEvent {
    return .{
        .stream = "bedd.dlq",
        .entry_id = "1700000000000-0",
        .fields_json = "{}",
        .event_type = "bedd.dlq",
        .payload_json = payload,
    };
}

test "decode reads the dlq envelope" {
    const entry = decode(testEvent(
        \\{"schemaVersion":"bedd.dlq.v1","source_stream":"inbox","entry_id":"5-0","source_event_type":"inbox.route","error":"SkillFailed","payload":{"id":"a","n":1}}
    ));
    try std.testing.expectEqualStrings("inbox", entry.source_stream);
    try std.testing.expectEqualStrings("inbox.route", entry.source_event_type);
    try std.testing.expectEqualStrings("5-0", entry.origin_entry_id);
    try std.testing.expectEqualStrings("SkillFailed", entry.error_name);
    try std.testing.expectEqualStrings("{\"id\":\"a\",\"n\":1}", entry.payload_json);
    try std.testing.expectEqual(@as(?i64, 1700000000000), entry.timestampMs());
}

test "decode keeps nested objects and braces inside strings intact" {
    const entry = decode(testEvent(
        \\{"source_stream":"inbox","error":"E","payload":{"a":{"b":[1,2]},"s":"}}not the end{"}}
    ));
    try std.testing.expectEqualStrings("{\"a\":{\"b\":[1,2]},\"s\":\"}}not the end{\"}", entry.payload_json);
}

test "decode surfaces a malformed envelope rather than dropping it" {
    const entry = decode(testEvent("{\"nope\":true}"));
    try std.testing.expectEqualStrings("unknown", entry.source_stream);
    try std.testing.expectEqualStrings("unknown", entry.error_name);
    // Pre-envelope entries have no source_event_type; replay falls back instead
    // of inventing one.
    try std.testing.expectEqualStrings("", entry.source_event_type);
}

test "filters match on error substring and exact source" {
    const entry = decode(testEvent(
        \\{"source_stream":"inbox","error":"SkillFailed","payload":{}}
    ));
    try std.testing.expect(matches(entry, .{ .error_filter = "Skill" }));
    try std.testing.expect(!matches(entry, .{ .error_filter = "Timeout" }));
    try std.testing.expect(matches(entry, .{ .source_filter = "inbox" }));
    try std.testing.expect(!matches(entry, .{ .source_filter = "inbo" }));
}
