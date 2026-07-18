const std = @import("std");

/// Skill-exchange kinds — route *computation* on streams (not message storage).
pub const ExchangeKind = enum {
    direct, // exact event_type / routing_key
    topic, // dotted patterns: * = one word, # = multi-word
    headers, // match JSON field key=value bindings
    fanout, // all bindings on the stream

    pub fn parse(s: []const u8) ExchangeKind {
        if (std.ascii.eqlIgnoreCase(s, "topic")) return .topic;
        if (std.ascii.eqlIgnoreCase(s, "headers")) return .headers;
        if (std.ascii.eqlIgnoreCase(s, "fanout")) return .fanout;
        return .direct;
    }

    pub fn name(self: ExchangeKind) []const u8 {
        return switch (self) {
            .direct => "direct",
            .topic => "topic",
            .headers => "headers",
            .fanout => "fanout",
        };
    }
};

/// Topic match: words separated by `.`
/// `*` = exactly one word, `#` = zero or more words.
pub fn topicMatch(pattern: []const u8, routing_key: []const u8) bool {
    if (std.mem.eql(u8, pattern, "#")) return true;
    if (std.mem.eql(u8, pattern, "*")) {
        return std.mem.indexOfScalar(u8, routing_key, '.') == null and routing_key.len > 0;
    }
    return topicMatchRec(pattern, routing_key);
}

fn topicMatchRec(pattern: []const u8, key: []const u8) bool {
    var pi: usize = 0;
    var ki: usize = 0;
    while (pi < pattern.len) {
        if (pattern[pi] == '#') {
            pi += 1;
            if (pi < pattern.len and pattern[pi] == '.') pi += 1;
            if (pi >= pattern.len) return true;
            var k = ki;
            while (true) {
                if (topicMatchRec(pattern[pi..], key[k..])) return true;
                if (k >= key.len) break;
                const next = std.mem.indexOfScalarPos(u8, key, k, '.') orelse key.len;
                k = if (next < key.len) next + 1 else key.len;
                if (k > key.len) break;
            }
            return false;
        }
        if (pattern[pi] == '*') {
            pi += 1;
            if (pi < pattern.len and pattern[pi] == '.') pi += 1;
            if (ki >= key.len) return false;
            const next = std.mem.indexOfScalarPos(u8, key, ki, '.') orelse key.len;
            ki = if (next < key.len) next + 1 else key.len;
            continue;
        }
        const pend = std.mem.indexOfScalarPos(u8, pattern, pi, '.') orelse pattern.len;
        const kend = std.mem.indexOfScalarPos(u8, key, ki, '.') orelse key.len;
        if (pend - pi != kend - ki) return false;
        if (!std.mem.eql(u8, pattern[pi..pend], key[ki..kend])) return false;
        pi = if (pend < pattern.len) pend + 1 else pattern.len;
        ki = if (kend < key.len) kend + 1 else key.len;
    }
    return ki >= key.len;
}

/// Headers match: every `k=v` in binding (comma-separated) must appear as a JSON field.
pub fn headersMatch(binding: []const u8, fields_json: []const u8) bool {
    if (binding.len == 0) return true;
    var it = std.mem.splitScalar(u8, binding, ',');
    while (it.next()) |pair| {
        const t = std.mem.trim(u8, pair, " \t");
        if (t.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse return false;
        const k = std.mem.trim(u8, t[0..eq], " \t");
        const v = std.mem.trim(u8, t[eq + 1 ..], " \t");
        var needle_buf: [256]u8 = undefined;
        const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\":\"{s}\"", .{ k, v }) catch return false;
        if (std.mem.indexOf(u8, fields_json, needle) == null) {
            const needle2 = std.fmt.bufPrint(&needle_buf, "\"{s}\":{s}", .{ k, v }) catch return false;
            if (std.mem.indexOf(u8, fields_json, needle2) == null) return false;
        }
    }
    return true;
}

/// Skill cost for prefetch weighting (heavier skills → smaller batches).
pub fn skillCost(skill_name: []const u8) u32 {
    if (std.mem.indexOf(u8, skill_name, "wasm") != null) return 5;
    if (std.mem.eql(u8, skill_name, "schema_gate")) return 3;
    if (std.mem.eql(u8, skill_name, "fingerprint")) return 2;
    if (std.mem.eql(u8, skill_name, "redact")) return 2;
    if (std.mem.eql(u8, skill_name, "drop_fields")) return 2;
    if (std.mem.indexOfScalar(u8, skill_name, ',') != null) {
        var cost: u32 = 0;
        var it = std.mem.splitScalar(u8, skill_name, ',');
        while (it.next()) |p| {
            const t = std.mem.trim(u8, p, " \t");
            if (t.len == 0) continue;
            cost += skillCost(t);
        }
        return @max(cost, 1);
    }
    return 1;
}

pub fn effectivePrefetch(global_prefetch: i64, cost: u32) i64 {
    const c: i64 = @intCast(@max(cost, 1));
    const n = @divTrunc(global_prefetch, c);
    return @max(n, 1);
}

test "topicMatch basic" {
    try std.testing.expect(topicMatch("a.b", "a.b"));
    try std.testing.expect(!topicMatch("a.b", "a.c"));
    try std.testing.expect(topicMatch("a.*", "a.b"));
    try std.testing.expect(!topicMatch("a.*", "a.b.c"));
    try std.testing.expect(topicMatch("a.#", "a.b.c"));
    try std.testing.expect(topicMatch("#", "x.y.z"));
    try std.testing.expect(topicMatch("secure.*", "secure.doc"));
    try std.testing.expect(topicMatch("*.event", "demo.event"));
}

test "headersMatch" {
    const fields = "{\"event_type\":\"t\",\"env\":\"prod\",\"payload\":{}}";
    try std.testing.expect(headersMatch("env=prod", fields));
    try std.testing.expect(!headersMatch("env=dev", fields));
}

test "skillCost chain" {
    try std.testing.expect(skillCost("echo") == 1);
    try std.testing.expect(skillCost("redact,fingerprint") >= 3);
}
