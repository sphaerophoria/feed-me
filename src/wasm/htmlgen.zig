const std = @import("std");
const sphtud = @import("sphtud");

pub fn HtmlWriter(comptime Writer: type) type {
    return struct {
        inner: Writer,
        state: enum {
            default,
            in_open_tag,
        },

        const Self = @This();

        pub fn openTag(self: *Self, name: []const u8) !void {
            try self.endOpenIfOpen();
            try self.inner.print("<{s}", .{name});
            self.state = .in_open_tag;
        }

        pub fn selfClose(self: *Self) !void {
            switch (self.state) {
                .default => return error.InvalidState,
                .in_open_tag => {
                    try self.inner.writeAll("/>");
                    self.state = .default;
                },
            }
        }

        pub fn attribute(self: *Self, key: []const u8, value: []const u8) !void {
            if (self.state != .in_open_tag) return error.InvalidState;
            try self.inner.print(" {s}=\"{s}\"", .{ key, value });
        }

        pub fn content(self: *Self, val: []const u8) !void {
            try self.endOpenIfOpen();
            try self.inner.writeAll(val);
        }

        pub fn closeTag(self: *Self, name: []const u8) !void {
            try self.endOpenIfOpen();
            try self.inner.print("</{s}>", .{name});
        }

        fn endOpenIfOpen(self: *Self) !void {
            switch (self.state) {
                .default => {},
                .in_open_tag => {
                    try self.endOpenTag();
                    self.state = .default;
                },
            }
        }

        fn endOpenTag(self: *Self) !void {
            if (self.state != .in_open_tag) return error.InvalidState;
            try self.inner.writeAll(">");
        }
    };
}

pub fn htmlWriter(writer: anytype) HtmlWriter(@TypeOf(writer)) {
    return .{
        .inner = writer,
        .state = .default,
    };
}

test "HtmlWriter sanity" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    var writer = htmlWriter(buf.writer());

    try writer.openTag("div");
    try writer.attribute("hello", "world");

    try writer.openTag("table");

    try writer.openTag("tr");

    try writer.openTag("td");
    try writer.content("col 1");
    try writer.closeTag("td");

    try writer.openTag("td");
    try writer.content("col 2");
    try writer.closeTag("td");

    try writer.closeTag("tr");
    try writer.closeTag("table");
    try writer.closeTag("div");

    try std.testing.expectEqualSlices(u8, "<div hello=\"world\"><table><tr><td>col 1</td><td>col 2</td></tr></table></div>", buf.items);
}
