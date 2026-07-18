const std = @import("std");
const posix = std.posix;

var stopping = std.atomic.Value(bool).init(false);
var reload = std.atomic.Value(bool).init(false);

pub fn requestStop() void {
    stopping.store(true, .seq_cst);
}

pub fn shouldStop() bool {
    return stopping.load(.seq_cst);
}

pub fn requestReload() void {
    reload.store(true, .seq_cst);
}

pub fn takeReload() bool {
    return reload.swap(false, .seq_cst);
}

fn handleSignal(sig: i32) callconv(.C) void {
    if (sig == posix.SIG.TERM or sig == posix.SIG.INT) {
        requestStop();
    } else if (sig == posix.SIG.HUP) {
        requestReload();
    }
}

/// Install SIGTERM/SIGINT → stop, SIGHUP → reload tinder.
pub fn installSignals() void {
    const act = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.TERM, &act, null) catch {};
    posix.sigaction(posix.SIG.INT, &act, null) catch {};
    posix.sigaction(posix.SIG.HUP, &act, null) catch {};
}
