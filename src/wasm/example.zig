const std = @import("std");
const wsr = @import("wsr.zig");

pub fn returnErrorHook() void {
    const st = @errorReturnTrace().?;
    if (st.index == 0) {
        wsr.captureBacktrace();
    }
}

pub fn fails() !void {
    return error.UhOh; // Zig please call wsr.captureBacktrace()
}

pub fn fnB() !void {
    try fails();
}

pub fn fnA() !void {
    try fnB();
}

pub export fn init() void {
    const ret = fnA();
    ret catch |e| {
        wsr.print("{s}\n", .{@errorName(e)});
        wsr.printCapturedBacktrace();
    };
}

//pub fn main() !void {
//    const st = @errorReturnTrace().?;
//    const ret = fnA();
//    ret catch |e| {
//        std.debug.print("{s}\n", .{@errorName(e)});
//        std.debug.print("{}", .{st});
//        //std.debug.printCapturedBacktrace(0);
//    };
//}
