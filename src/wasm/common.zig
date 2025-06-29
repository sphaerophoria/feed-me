const std = @import("std");
const sphtud = @import("sphtud");
const wsr = @import("wsr.zig");

pub fn makeArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
}

pub fn logFailure(value: anytype) void {
    value catch |e| {
        // Stack trace in wasm in does not work correctly, so we manage it ourselves
        wsr.print("{s}", .{@errorName(e)});

        wsr.printCapturedBacktrace();
    };
}
