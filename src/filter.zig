const std = @import("std");
const skill = @import("skill/mod.zig");

/// NDJSON stdin → skill → stdout. The Bun-like path: use Bedd inside a worker
/// without competing for a consumer group (`bedd serve`).
pub fn run(
    allocator: std.mem.Allocator,
    skills_dir: []const u8,
    skill_name: []const u8,
    raw_payload: bool,
) !void {
    var reg = skill.Registry.init(allocator, skills_dir);
    defer reg.deinit();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var line_buf: [1024 * 1024]u8 = undefined;
    var ok: u64 = 0;
    var err_n: u64 = 0;
    var n: u64 = 0;

    while (true) {
        const line = (try stdin.readUntilDelimiterOrEof(&line_buf, '\n')) orelse break;
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        n += 1;

        var entry_buf: [32]u8 = undefined;
        const entry_id = std.fmt.bufPrint(&entry_buf, "filter-{d}", .{n}) catch "filter";

        const ctx = skill.SkillContext{
            .allocator = allocator,
            .stream = "filter",
            .entry_id = entry_id,
            .event_type = "bedd.filter",
        };

        const result = reg.run(skill_name, ctx, trimmed) catch |e| {
            err_n += 1;
            try stderr.print("{{\"ok\":false,\"n\":{d},\"error\":\"{s}\"}}\n", .{ n, @errorName(e) });
            continue;
        };
        defer result.deinit(allocator);
        ok += 1;

        if (raw_payload) {
            try stdout.writeAll(result.payload_json);
            try stdout.writeAll("\n");
        } else {
            // Prefer skill's cleaned payload over wrapSkill envelopes that re-embed input
            // (redact historically wraps with "input" — that would leak secrets on stdout).
            const emit = unwrapClean(result.payload_json) orelse result.payload_json;
            try stdout.writeAll(emit);
            try stdout.writeAll("\n");
        }
    }

    try stderr.print("bedd filter skill={s} lines={d} ok={d} err={d}\n", .{ skill_name, n, ok, err_n });
    if (err_n > 0) std.process.exit(1);
}

/// If skill wrapped as {"redacted":{...},...} or {"ok":true,"redacted":...}, emit the cleaned object.
fn unwrapClean(payload: []const u8) ?[]const u8 {
    for ([_][]const u8{ "\"redacted\"", "\"payload\"" }) |key| {
        const idx = std.mem.indexOf(u8, payload, key) orelse continue;
        var j = idx + key.len;
        while (j < payload.len and (payload[j] == ' ' or payload[j] == ':' or payload[j] == '\t')) : (j += 1) {}
        if (j >= payload.len) continue;
        if (payload[j] == '{') {
            const start = j;
            var depth: i32 = 0;
            var in_str = false;
            var escape = false;
            while (j < payload.len) : (j += 1) {
                const c = payload[j];
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
                    if (depth == 0) return payload[start .. j + 1];
                }
            }
        }
    }
    return null;
}
