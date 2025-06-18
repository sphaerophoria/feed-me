const std = @import("std");

const imported = struct {
    extern fn print(data: [*]u8, len: usize) void;
    extern fn replaceSelfContent(
        content_ptr: [*]const u8, content_len: usize,
        attribute_ptr: [*]const u8, attribute_len: usize,
    ) void;
    extern fn replaceElemContent(
        elem_id_ptr: [*]const u8, elem_id_len: usize,
        content_ptr: [*]const u8, content_len: usize,
        attribute_ptr: [*]const u8, attribute_len: usize,
    ) void;
    extern fn requestPut(
        url_ptr: [*]const u8, url_len: usize,
        body_ptr: [*]const u8, body_len: usize,
    ) void;
};

const exported = struct {
    pub export fn getInputBuffer() [*]u8 {
        return Global.get().input_buffer.ptr;
    }

    pub export fn allocateInputBuffer(size: usize) void {
        const input_buffer = &Global.get().input_buffer;
        std.heap.wasm_allocator.free(input_buffer.*);
        input_buffer.* = std.heap.wasm_allocator.alloc(u8, size) catch return;
    }
};

// Force reference to ensure in final executable
comptime {
    _ = exported;
}

pub fn replaceSelfContent(content: []const u8, attribute: []const u8) void {
    imported.replaceSelfContent(
        content.ptr, content.len,
        attribute.ptr, attribute.len,
    );
}

pub fn replaceElemContent(elem_id: []const u8, content: []const u8, attribute: []const u8) void {
    imported.replaceElemContent(
        elem_id.ptr, elem_id.len,
        content.ptr, content.len,
        attribute.ptr, attribute.len,
    );
}

pub fn requestPut(url: []const u8, body: []const u8) void {
    imported.requestPut(
        url.ptr, url.len,
        body.ptr, body.len,
    );
}

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = return_address;
    print("{s}", .{msg});
    if (stack_trace) |st| {
        print("With stacktrace {}", .{st});
    }
    @trap();
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    imported.print(slice.ptr, slice.len);
}

const Global = struct {
    input_buffer: []u8,

    var instance: ?Global = null;

    fn get() *Global {
        if (instance == null) {
            instance = .{
                .input_buffer = &.{},
            };
        }

        return &instance.?;
    }
};

pub fn getInputBuffer() []const u8 {
    return Global.get().input_buffer;
}
