const std = @import("std");
const exchange = @import("exchange.zig");
const jsonx = @import("jsonx.zig");

/// One skill binding on a stream (skill-exchange plane).
pub const Route = struct {
    stream: []const u8,
    event_type: []const u8, // pattern or "*" ; also used as routing_key for topic
    skill: []const u8, // single skill or comma-separated chain
    publish_stream: []const u8,
    publish_event_type: []const u8,
    exchange_kind: exchange.ExchangeKind = .direct,
    headers: []const u8 = "", // "k=v,k2=v2" for headers exchange
    recovery_skill: []const u8 = "", // on failure, run this before DLQ
    confirm: bool = true, // require successful publish before ack
};

pub const Tinder = struct {
    allocator: std.mem.Allocator,
    routes: []Route,
    owned_blob: ?[]u8 = null,

    pub fn deinit(self: *Tinder) void {
        for (self.routes) |r| {
            self.allocator.free(r.stream);
            self.allocator.free(r.event_type);
            self.allocator.free(r.skill);
            self.allocator.free(r.publish_stream);
            self.allocator.free(r.publish_event_type);
            if (r.headers.len > 0) self.allocator.free(r.headers);
            if (r.recovery_skill.len > 0) self.allocator.free(r.recovery_skill);
        }
        self.allocator.free(self.routes);
        if (self.owned_blob) |b| self.allocator.free(b);
    }

    /// First matching binding (direct/topic/headers). Fanout callers should use matchAll.
    pub fn match(self: *const Tinder, stream: []const u8, event_type: []const u8) ?Route {
        return self.matchWithFields(stream, event_type, "{}");
    }

    pub fn matchWithFields(self: *const Tinder, stream: []const u8, event_type: []const u8, fields_json: []const u8) ?Route {
        for (self.routes) |r| {
            if (!std.mem.eql(u8, r.stream, stream)) continue;
            if (bindingMatches(r, event_type, fields_json)) return r;
        }
        return null;
    }

    /// All matching bindings (fanout + overlapping topic/direct).
    pub fn matchAll(
        self: *const Tinder,
        allocator: std.mem.Allocator,
        stream: []const u8,
        event_type: []const u8,
        fields_json: []const u8,
    ) ![]Route {
        var list = std.ArrayList(Route).init(allocator);
        errdefer list.deinit();
        for (self.routes) |r| {
            if (!std.mem.eql(u8, r.stream, stream)) continue;
            if (bindingMatches(r, event_type, fields_json)) try list.append(r);
        }
        return try list.toOwnedSlice();
    }

    pub fn uniqueStreams(self: *const Tinder, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();
        for (self.routes) |r| {
            var found = false;
            for (list.items) |s| {
                if (std.mem.eql(u8, s, r.stream)) {
                    found = true;
                    break;
                }
            }
            if (!found) try list.append(r.stream);
        }
        return try list.toOwnedSlice();
    }

    /// Max skill cost among bindings for a stream (for prefetch sizing).
    pub fn maxCostForStream(self: *const Tinder, stream: []const u8) u32 {
        var max_c: u32 = 1;
        for (self.routes) |r| {
            if (!std.mem.eql(u8, r.stream, stream)) continue;
            max_c = @max(max_c, exchange.skillCost(r.skill));
        }
        return max_c;
    }
};

fn bindingMatches(r: Route, event_type: []const u8, fields_json: []const u8) bool {
    return switch (r.exchange_kind) {
        .fanout => true,
        .direct => std.mem.eql(u8, r.event_type, "*") or std.mem.eql(u8, r.event_type, event_type),
        .topic => exchange.topicMatch(r.event_type, event_type),
        .headers => exchange.headersMatch(r.headers, fields_json),
    };
}

pub fn defaultTinder(allocator: std.mem.Allocator) !Tinder {
    const routes = try allocator.alloc(Route, 1);
    routes[0] = .{
        .stream = try allocator.dupe(u8, "inbox"),
        .event_type = try allocator.dupe(u8, "*"),
        .skill = try allocator.dupe(u8, "echo"),
        .publish_stream = try allocator.dupe(u8, "outbox"),
        .publish_event_type = try allocator.dupe(u8, "bedd.strike.result"),
        .exchange_kind = .direct,
        .headers = "",
        .recovery_skill = "",
        .confirm = true,
    };
    return .{ .allocator = allocator, .routes = routes };
}

pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Tinder {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const blob = try file.readToEndAlloc(allocator, 2 * 1024 * 1024);
    errdefer allocator.free(blob);
    var tinder = try parseTinderJson(allocator, blob);
    tinder.owned_blob = blob;
    return tinder;
}

pub fn loadOrDefault(allocator: std.mem.Allocator, path: ?[]const u8) !Tinder {
    if (path) |p| {
        return loadFromFile(allocator, p) catch |err| {
            std.log.warn("failed to load tinder {s}: {s}; using defaults", .{ p, @errorName(err) });
            return defaultTinder(allocator);
        };
    }
    return defaultTinder(allocator);
}

fn parseTinderJson(allocator: std.mem.Allocator, blob: []const u8) !Tinder {
    var routes = std.ArrayList(Route).init(allocator);
    errdefer {
        for (routes.items) |r| {
            allocator.free(r.stream);
            allocator.free(r.event_type);
            allocator.free(r.skill);
            allocator.free(r.publish_stream);
            allocator.free(r.publish_event_type);
            if (r.headers.len > 0) allocator.free(r.headers);
            if (r.recovery_skill.len > 0) allocator.free(r.recovery_skill);
        }
        routes.deinit();
    }

    const key = std.mem.indexOf(u8, blob, "\"routes\"") orelse return error.InvalidTinder;
    var i = key;
    while (i < blob.len and blob[i] != '[') : (i += 1) {}
    if (i >= blob.len) return error.InvalidTinder;
    i += 1;

    while (i < blob.len) {
        while (i < blob.len and blob[i] != '{' and blob[i] != ']') : (i += 1) {}
        if (i >= blob.len or blob[i] == ']') break;
        const start = i;
        var depth: i32 = 0;
        var in_str = false;
        var escape = false;
        while (i < blob.len) : (i += 1) {
            const c = blob[i];
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
            if (c == '{') depth += 1;
            if (c == '}') {
                depth -= 1;
                if (depth == 0) {
                    i += 1;
                    break;
                }
            }
        }
        const obj = blob[start..i];
        const stream = jsonx.getStringField(obj, "stream") orelse continue;
        const skill = jsonx.getStringField(obj, "skill") orelse continue;
        const event_type = jsonx.getStringField(obj, "event_type") orelse
            jsonx.getStringField(obj, "routing_key") orelse "*";
        const publish_stream = jsonx.getStringField(obj, "publish_stream") orelse "outbox";
        const publish_event_type = jsonx.getStringField(obj, "publish_event_type") orelse "bedd.strike.result";
        const ex_s = jsonx.getStringField(obj, "exchange") orelse
            jsonx.getStringField(obj, "exchange_kind") orelse "direct";
        const headers = jsonx.getStringField(obj, "headers") orelse "";
        const recovery = jsonx.getStringField(obj, "recovery_skill") orelse "";
        const confirm = parseBoolField(obj, "confirm", true);

        try routes.append(.{
            .stream = try allocator.dupe(u8, stream),
            .event_type = try allocator.dupe(u8, event_type),
            .skill = try allocator.dupe(u8, skill),
            .publish_stream = try allocator.dupe(u8, publish_stream),
            .publish_event_type = try allocator.dupe(u8, publish_event_type),
            .exchange_kind = exchange.ExchangeKind.parse(ex_s),
            .headers = if (headers.len > 0) try allocator.dupe(u8, headers) else "",
            .recovery_skill = if (recovery.len > 0) try allocator.dupe(u8, recovery) else "",
            .confirm = confirm,
        });
    }

    if (routes.items.len == 0) return error.InvalidTinder;
    return .{
        .allocator = allocator,
        .routes = try routes.toOwnedSlice(),
    };
}

fn parseBoolField(obj: []const u8, key: []const u8, fallback: bool) bool {
    var needle_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&needle_buf, "\"{s}\"", .{key}) catch return fallback;
    const idx = std.mem.indexOf(u8, obj, needle) orelse return fallback;
    var j = idx + needle.len;
    while (j < obj.len and (obj[j] == ' ' or obj[j] == ':' or obj[j] == '\t')) : (j += 1) {}
    if (j + 4 <= obj.len and std.mem.eql(u8, obj[j .. j + 4], "true")) return true;
    if (j + 5 <= obj.len and std.mem.eql(u8, obj[j .. j + 5], "false")) return false;
    return fallback;
}

test "default tinder matches inbox" {
    var t = try defaultTinder(std.testing.allocator);
    defer t.deinit();
    const r = t.match("inbox", "anything");
    try std.testing.expect(r != null);
    try std.testing.expectEqualStrings("echo", r.?.skill);
}

test "parse tinder json" {
    const sample =
        \\{"routes":[{"stream":"inbox","event_type":"*","skill":"echo","publish_stream":"outbox","publish_event_type":"bedd.strike.result"}]}
    ;
    var t = try parseTinderJson(std.testing.allocator, sample);
    defer t.deinit();
    try std.testing.expectEqual(@as(usize, 1), t.routes.len);
}

test "topic binding matches" {
    const sample =
        \\{"routes":[{"stream":"inbox","exchange":"topic","event_type":"secure.*","skill":"redact","publish_stream":"outbox","publish_event_type":"bedd.redacted","recovery_skill":"passthrough"}]}
    ;
    var t = try parseTinderJson(std.testing.allocator, sample);
    defer t.deinit();
    try std.testing.expect(t.match("inbox", "secure.doc") != null);
    try std.testing.expect(t.match("inbox", "public.doc") == null);
    try std.testing.expectEqualStrings("passthrough", t.routes[0].recovery_skill);
}
