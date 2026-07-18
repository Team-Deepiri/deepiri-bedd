const std = @import("std");
const tinder = @import("tinder.zig");
const skill = @import("skill/mod.zig");
const topics_desc = @import("topics_desc.zig");

pub const ValidationIssue = struct {
    level: enum { err, warn },
    message: []const u8,
};

/// Validate a tinder file: parse routes, warn on unknown skills / odd streams.
pub fn validateFile(allocator: std.mem.Allocator, path: []const u8) ![]ValidationIssue {
    var issues = std.ArrayList(ValidationIssue).init(allocator);
    errdefer {
        for (issues.items) |i| allocator.free(i.message);
        issues.deinit();
    }

    var loaded = tinder.loadFromFile(allocator, path) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "failed to load tinder: {s}", .{@errorName(err)});
        try issues.append(.{ .level = .err, .message = msg });
        return try issues.toOwnedSlice();
    };
    defer loaded.deinit();

    if (loaded.routes.len == 0) {
        try issues.append(.{
            .level = .err,
            .message = try allocator.dupe(u8, "no routes defined"),
        });
    }

    // Known builtin names via listing into a set-like check
    var known = std.StringHashMap(void).init(allocator);
    defer known.deinit();
    // seed from builtins by probing registry run list text
    var tmp = std.ArrayList(u8).init(allocator);
    defer tmp.deinit();
    try skill.Registry.listBuiltins(tmp.writer());
    var lines = std.mem.splitScalar(u8, tmp.items, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t-");
        if (trimmed.len == 0) continue;
        const name_end = std.mem.indexOf(u8, trimmed, " ") orelse trimmed.len;
        try known.put(try allocator.dupe(u8, trimmed[0..name_end]), {});
    }
    defer {
        var it = known.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
    }

    for (loaded.routes) |r| {
        if (r.stream.len == 0) {
            try issues.append(.{ .level = .err, .message = try allocator.dupe(u8, "route with empty stream") });
        }
        if (r.skill.len == 0) {
            try issues.append(.{ .level = .err, .message = try allocator.dupe(u8, "route with empty skill") });
        } else if (!known.contains(r.skill) and !std.mem.endsWith(u8, r.skill, "_skill")) {
            const msg = try std.fmt.allocPrint(allocator, "unknown skill '{s}' on stream {s}", .{ r.skill, r.stream });
            try issues.append(.{ .level = .warn, .message = msg });
        }
        if (r.publish_stream.len == 0) {
            try issues.append(.{ .level = .err, .message = try allocator.dupe(u8, "route with empty publish_stream") });
        }

        var known_topic = false;
        for (topics_desc.catalog) |d| {
            if (std.mem.eql(u8, d.name, r.stream)) {
                known_topic = true;
                break;
            }
        }
        if (!known_topic) {
            const msg = try std.fmt.allocPrint(allocator, "stream '{s}' not in ModelKit catalog (ok if intentional)", .{r.stream});
            try issues.append(.{ .level = .warn, .message = msg });
        }
    }

    return try issues.toOwnedSlice();
}

pub fn printValidation(allocator: std.mem.Allocator, path: []const u8) !u8 {
    const issues = try validateFile(allocator, path);
    defer {
        for (issues) |i| allocator.free(i.message);
        allocator.free(issues);
    }
    const out = std.io.getStdOut().writer();
    try out.print("flint tinder validate: {s}\n", .{path});
    var errors: u32 = 0;
    var warns: u32 = 0;
    for (issues) |i| {
        const tag: []const u8 = if (i.level == .err) "error" else "warn";
        try out.print("  [{s}] {s}\n", .{ tag, i.message });
        if (i.level == .err) errors += 1 else warns += 1;
    }
    if (issues.len == 0) try out.writeAll("  ok — no issues\n");
    try out.print("summary: errors={d} warns={d}\n", .{ errors, warns });
    return if (errors > 0) 1 else 0;
}

test "validate example tinder" {
    // may or may not exist depending on cwd; skip if missing
    std.fs.cwd().access("tinder.example.json", .{}) catch return;
    const issues = try validateFile(std.testing.allocator, "tinder.example.json");
    defer {
        for (issues) |i| std.testing.allocator.free(i.message);
        std.testing.allocator.free(issues);
    }
    // Should parse without hard errors for our example
    for (issues) |i| {
        try std.testing.expect(i.level != .err);
    }
}
