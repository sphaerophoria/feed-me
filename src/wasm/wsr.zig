const std = @import("std");

const imported = struct {
    extern fn print(data: [*]const u8, len: usize) void;
    extern fn replaceSelfProperty(
        content_ptr: [*]const u8,
        content_len: usize,
        property_ptr: [*]const u8,
        property_len: usize,
    ) void;
    extern fn replaceElemProperty(
        elem_id_ptr: [*]const u8,
        elem_id_len: usize,
        content_ptr: [*]const u8,
        content_len: usize,
        property_ptr: [*]const u8,
        property_len: usize,
    ) void;
    extern fn getElemProperty(
        elem_id_ptr: [*]const u8,
        elem_id_len: usize,
        property_ptr: [*]const u8,
        property_len: usize,
    ) void;
    extern fn appendToElem(
        elem_id_ptr: [*]const u8,
        elem_id_len: usize,
        content_ptr: [*]const u8,
        content_len: usize,
    ) void;
    extern fn requestFetch(
        url_ptr: [*]const u8,
        url_len: usize,
        body_ptr: [*]const u8,
        body_len: usize,
        method_ptr: [*]const u8,
        method_len: usize,
        callback_ptr: [*]const u8,
        callback_len: usize,
    ) void;
    extern fn deleteElemByQuery(
        query_ptr: [*]const u8,
        query_len: usize,
    ) void;
    extern fn getSelfAttribute(
        attr_ptr: [*]const u8,
        attr_len: usize,
    ) void;
    extern fn getSelfProperty(
        prop_ptr: [*]const u8,
        prop_len: usize,
    ) void;
    extern fn getEventProperty(
        prop_ptr: [*]const u8,
        prop_len: usize,
    ) void;

    extern fn captureBacktrace(idx: usize) void;
    extern fn printCapturedBacktrace(idx: usize) void;
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

    pub export fn crashycrashy() void {
        @trap();
    }
};

// Force reference to ensure in final executable
comptime {
    _ = exported;
}

pub fn replaceSelfProperty(content: []const u8, property: []const u8) void {
    imported.replaceSelfProperty(
        content.ptr,
        content.len,
        property.ptr,
        property.len,
    );
}

pub fn replaceElemProperty(elem_id: []const u8, content: []const u8, property: []const u8) void {
    imported.replaceElemProperty(
        elem_id.ptr,
        elem_id.len,
        content.ptr,
        content.len,
        property.ptr,
        property.len,
    );
}

pub fn getElemProperty(elem_id: []const u8, property: []const u8) void {
    imported.getElemProperty(
        elem_id.ptr,
        elem_id.len,
        property.ptr,
        property.len,
    );
}

pub fn appendToElem(elem_id: []const u8, content: []const u8) void {
    imported.appendToElem(
        elem_id.ptr,
        elem_id.len,
        content.ptr,
        content.len,
    );
}

pub fn deleteElemByQuery(query: []const u8) void {
    imported.deleteElemByQuery(query.ptr, query.len);
}

// FIXME: Deprecated
pub fn requestPut(url: []const u8, body: []const u8) void {
    imported.requestFetch(
        url.ptr,
        url.len,
        body.ptr,
        body.len,
        undefined,
        0,
        undefined,
        0,
    );
}

pub const RequestFetch = struct {
    url: []const u8,
    method: []const u8,
    body: []const u8 = &.{},
    callback: []const u8 = &.{},

    pub fn init(url: []const u8, method: []const u8) RequestFetch {
        return .{
            .url = url,
            .method = method,
        };
    }

    pub fn addBody(self: *RequestFetch, body: []const u8) void {
        self.body = body;
    }

    pub fn addCallback(self: *RequestFetch, callback: []const u8) void {
        self.callback = callback;
    }

    pub fn run(self: RequestFetch) void {
        imported.requestFetch(
            self.url.ptr,
            self.url.len,
            self.body.ptr,
            self.body.len,
            self.method.ptr,
            self.method.len,
            self.callback.ptr,
            self.callback.len,
        );
    }
};

pub fn getSelfAttribute(name: []const u8) void {
    imported.getSelfAttribute(name.ptr, name.len);
}

pub fn getSelfProperty(name: []const u8) void {
    imported.getSelfProperty(name.ptr, name.len);
}

pub fn getEventProperty(name: []const u8) void {
    imported.getEventProperty(name.ptr, name.len);
}

pub fn panic(msg: []const u8, stack_trace: ?*std.builtin.StackTrace, return_address: ?usize) noreturn {
    _ = return_address;
    print("{s}", .{msg});
    if (stack_trace) |st| {
        print("With stacktrace {any}", .{st.instruction_addresses});
    }
    @trap();
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
    imported.print(slice.ptr, slice.len);
}

pub fn writeStdout(buf: []const u8) void {
    imported.print(buf.ptr, buf.len);
}

pub fn captureBacktrace(idx: usize) void {
    imported.captureBacktrace(idx);
}

pub fn printCapturedBacktrace(idx: usize) void {
    imported.printCapturedBacktrace(idx);
}

pub fn attachWsrError(err: anytype) @TypeOf(err) {
    if (true) return err;
    const ti = @typeInfo(@TypeOf(err));
    switch (ti) {
        .error_set => {
            captureBacktrace();
            return err;
        },
        .error_union => {
            return err catch |e| {
                captureBacktrace();
                return e;
            };

        },
        else => @compileError("Not an error"),
    }
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
