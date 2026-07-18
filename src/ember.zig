const std = @import("std");

/// In-process metrics + last-N strike traces.
pub const Ember = struct {
    strikes_ok: u64 = 0,
    strikes_err: u64 = 0,
    publishes: u64 = 0,
    acks: u64 = 0,
    reads: u64 = 0,
    mutex: std.Thread.Mutex = .{},
    ring: [16]Trace = [_]Trace{.{}} ** 16,
    ring_i: usize = 0,

    pub const Trace = struct {
        stream: [96]u8 = [_]u8{0} ** 96,
        stream_len: usize = 0,
        skill: [48]u8 = [_]u8{0} ** 48,
        skill_len: usize = 0,
        ok: bool = false,
        ms: u64 = 0,
    };

    pub fn record(self: *Ember, stream: []const u8, skill: []const u8, ok: bool, ms: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (ok) self.strikes_ok += 1 else self.strikes_err += 1;
        var t = Trace{ .ok = ok, .ms = ms };
        const sl = @min(stream.len, t.stream.len);
        @memcpy(t.stream[0..sl], stream[0..sl]);
        t.stream_len = sl;
        const kl = @min(skill.len, t.skill.len);
        @memcpy(t.skill[0..kl], skill[0..kl]);
        t.skill_len = kl;
        self.ring[self.ring_i % self.ring.len] = t;
        self.ring_i += 1;
    }

    pub fn print(self: *Ember, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try writer.print(
            "ember strikes_ok={d} strikes_err={d} publishes={d} acks={d} reads={d}\n",
            .{ self.strikes_ok, self.strikes_err, self.publishes, self.acks, self.reads },
        );
    }
};

test "ember records" {
    var e = Ember{};
    e.record("document.artifacts", "echo", true, 3);
    try std.testing.expectEqual(@as(u64, 1), e.strikes_ok);
}
