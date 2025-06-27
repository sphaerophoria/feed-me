const std = @import("std");
const wsr = @import("wsr.zig");

pub fn makeArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
}

pub const StackTraceFormatter = struct {
    stack_trace: *std.builtin.StackTrace,

    pub fn format(
        self: StackTraceFormatter,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;
        try writer.print("{any}", .{self.stack_trace.instruction_addresses[0..self.stack_trace.index]});
        try writer.writeAll("\n");
        //std.debug.writeStackTrace(self.stack_trace.*, writer, debug_info, .no_color) catch |err| {
        //    try writer.print("Unable to print stack trace: {s}\n", .{@errorName(err)});
        //};
    }
};

pub fn logFailure(value: anytype) void {
    value catch |e| {
        // Stack trace in wasm in does not work correctly, so we manage it ourselves
        wsr.print("{s}", .{@errorName(e)});

        wsr.printCapturedBacktrace();
    };
}
