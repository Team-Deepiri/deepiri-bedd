const std = @import("std");
const bus = @import("bus.zig");
const config = @import("config.zig");
const strike = @import("strike.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // argv[0]
    const command = args.next() orelse "help";

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printHelp();
        return;
    }

    if (std.mem.eql(u8, command, "version")) {
        try std.io.getStdOut().writer().print("deepiri-flint {s}\n", .{config.version});
        return;
    }

    if (std.mem.eql(u8, command, "doctor")) {
        const cfg = try config.loadFromEnv(allocator);
        defer cfg.deinit(allocator);
        try bus.doctor(allocator, cfg);
        return;
    }

    if (std.mem.eql(u8, command, "strike")) {
        const cfg = try config.loadFromEnv(allocator);
        defer cfg.deinit(allocator);
        const stream = args.next() orelse "document.artifacts";
        const event_type = args.next() orelse "document.artifacts.route";
        try strike.dryRun(allocator, cfg, stream, event_type);
        return;
    }

    if (std.mem.eql(u8, command, "serve")) {
        const cfg = try config.loadFromEnv(allocator);
        defer cfg.deinit(allocator);
        try std.io.getStdOut().writer().print(
            "flint: serve mode stub — would consume via Sugar Glider at {s}\n",
            .{cfg.sugar_glider_url},
        );
        return;
    }

    try std.io.getStdErr().writer().print("flint: unknown command '{s}'\n", .{command});
    try printHelp();
    std.process.exit(1);
}

fn printHelp() !void {
    const out = std.io.getStdOut().writer();
    try out.writeAll(
        \\deepiri-flint — stream-native AI worker runtime (Zig)
        \\
        \\Usage:
        \\  flint help
        \\  flint version
        \\  flint doctor              Check Sugar Glider / env
        \\  flint strike [stream] [event_type]   Dry-run one strike
        \\  flint serve               Run consumer loop (stub in v0)
        \\
        \\Env:
        \\  FLINT_SUGAR_GLIDER_URL   default http://127.0.0.1:8081
        \\  FLINT_SENDER             default flint
        \\  SYNAPSE_SUGAR_GLIDER_URL alias for FLINT_SUGAR_GLIDER_URL
        \\
    );
}
