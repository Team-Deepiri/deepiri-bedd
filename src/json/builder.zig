const std = @import("std");

pub const Obj = struct {
    allocator: std.mem.Allocator,
    buf: std.ArrayList(u8),
    first: bool = true,

    pub fn init(allocator: std.mem.Allocator) Obj {
        return .{ .allocator = allocator, .buf = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *Obj) void {
        self.buf.deinit();
    }

    pub fn begin(self: *Obj) !void {
        try self.buf.append('{');
        self.first = true;
    }

    pub fn end(self: *Obj) ![]u8 {
        try self.buf.append('}');
        return try self.buf.toOwnedSlice();
    }

    fn comma(self: *Obj) !void {
        if (!self.first) try self.buf.append(',');
        self.first = false;
    }

    pub fn putRaw(self: *Obj, key: []const u8, raw_json: []const u8) !void {
        try self.comma();
        try self.buf.writer().print("\"{s}\":{s}", .{ key, raw_json });
    }

    pub fn putString(self: *Obj, key: []const u8, value: []const u8) !void {
        try self.comma();
        try self.buf.writer().print("\"{s}\":\"{s}\"", .{ key, value });
    }

    pub fn putBool(self: *Obj, key: []const u8, value: bool) !void {
        try self.comma();
        try self.buf.writer().print("\"{s}\":{}", .{ key, value });
    }

    pub fn putInt(self: *Obj, key: []const u8, value: i64) !void {
        try self.comma();
        try self.buf.writer().print("\"{s}\":{d}", .{ key, value });
    }
};

test "builder object" {
    var o = Obj.init(std.testing.allocator);
    try o.begin();
    try o.putString("k", "v");
    try o.putBool("ok", true);
    const s = try o.end();
    defer std.testing.allocator.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "\"k\":\"v\"") != null);
}
