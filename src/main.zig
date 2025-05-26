const sphtud = @import("sphtud");
const std = @import("std");
const api = @import("api.zig");
const Db = @import("Db.zig");

const HttpContext = struct {
    resource_dir: std.fs.Dir,
    scratch: *sphtud.alloc.ScratchAlloc,
    db: Db,
    // For memory tracking purposes
    root_alloc: *sphtud.alloc.Sphalloc,

    pub fn init(root_alloc: *sphtud.alloc.Sphalloc, scratch: *sphtud.alloc.ScratchAlloc, db_path: [:0]const u8) !HttpContext {
        return .{
            .resource_dir = try std.fs.cwd().openDir("res", .{}),
            .scratch = scratch,
            .db = try Db.init(db_path),
            .root_alloc = root_alloc,
        };
    }

    pub fn deinit(self: *HttpContext) void {
        self.db.deinit();
    }

    pub fn serve(self: *HttpContext, http_reader: *sphtud.http.HttpReader, connection: std.net.Stream) !void {
        const checkpoint = self.scratch.checkpoint();
        defer self.scratch.restore(checkpoint);

        // FIXME: Sanitize
        const target = (try http_reader.getTarget(self.scratch.allocator())).?;
        const body = http_reader.getBody();
        const parsed_target = try api.Target.parse(target, http_reader.header.?.method);

        switch (parsed_target) {
            .add_ingredient => {
                const params = try parseJsonBody(api.AddIngredient, self.scratch.allocator(), body);
                try params.validate();

                const ingredient = try self.db.addIngredient(params.name);
                try respondJson(self.scratch.allocator(), connection, ingredient);
            },
            .get_ingredients => {
                const ingredients = try self.db.getIngredients(self.scratch.allocator());
                try respondJson(self.scratch.allocator(), connection, ingredients);
            },
            .get_ingredient => |id| {
                const ingredient = try self.db.getIngredient(id, self.scratch.allocator());
                try respondJson(self.scratch.allocator(), connection, ingredient);
            },
            .modify_ingredient => |id| {
                const params = try parseJsonBody(api.ModifyIngredientParams, self.scratch.allocator(), body);
                try params.validate();

                const ingredient = try self.db.modifyIngredient(
                    self.scratch.allocator(),
                    id,
                    params,
                );
                try respondJson(self.scratch.allocator(), connection, ingredient);
            },
            .get_properties => {
                const property = try self.db.getProperties(self.scratch.allocator());
                try respondJson(self.scratch.allocator(), connection, property);
            },
            .add_property => {
                const params = try parseJsonBody(api.AddProperty, self.scratch.allocator(), body);
                try params.validate();

                const property = try self.db.addProperty(params.name);
                try respondJson(self.scratch.allocator(), connection, property);
            },
            .add_ingredient_property => {
                const params = try parseJsonBody(api.AddIngredientPropertyParams, self.scratch.allocator(), body);

                const ingredient_property = try self.db.addIngredientProperty(params);
                try respondJson(self.scratch.allocator(), connection, ingredient_property);
            },
            .modify_ingredient_property => |id| {
                const params = try parseJsonBody(api.ModifyIngredientPropertyParams, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyIngredientProperty(id, params.value);
                try respondEmpty(connection);
            },
            .redirect_to_index => {
                var writer = sphtud.http.httpWriter(connection.writer());
                try writer.start(.{ .status = .moved_permanently, .content_length = 0 });
                try writer.appendHeader("Location", "/index.html");
                try writer.writeBody("");
            },
            .memory_usage => {
                var response_buf = sphtud.util.RuntimeBoundedArray(u8).fromBuf(try self.scratch.allocator().alloc(u8, 8192));
                var w = response_buf.writer();

                const memory_snapshot = try sphtud.alloc.MemoryTracker.snapshot(self.scratch.allocator(), self.root_alloc, 100);
                try w.print("Memory usage\n", .{});
                for (memory_snapshot) |elem| {
                    try w.print("{s}: {d}\n", .{ elem.name, elem.memory_used });
                }

                var http_writer = sphtud.http.httpWriter(connection.writer());
                try http_writer.start(.{
                    .status = .ok,
                    .content_length = response_buf.items.len,
                    .content_type = "text/plain",
                });
                try http_writer.writeBody(response_buf.items);
            },
            .filesystem => |fs_path| {
                const target_end = std.mem.indexOfScalar(u8, fs_path, '?') orelse fs_path.len;
                const buf = self.scratch.allocMax(u8);
                const content = try self.resource_dir.readFile(fs_path[1..target_end], buf);
                self.scratch.shrinkTo(content.ptr + content.len);

                const content_type = contentTypeFromExtension(fs_path);

                var writer = sphtud.http.httpWriter(connection.writer());
                try writer.start(.{
                    .status = .ok,
                    .content_length = content.len,
                    .content_type = content_type,
                });
                try writer.writeBody(content);
            },
        }
    }

    fn parseJsonBody(comptime T: type, leaky: std.mem.Allocator, body: sphtud.util.RuntimeSegmentedList(u8).Slice) !T {
        var body_reader = body.reader();
        var jw = std.json.reader(leaky, body_reader.generic());
        return try std.json.parseFromTokenSourceLeaky(T, leaky, &jw, .{});
    }

    fn respondJson(scratch: std.mem.Allocator, connection: std.net.Stream, response: anytype) !void {
        const response_str = try std.json.stringifyAlloc(scratch, response, .{
            .emit_null_optional_fields = false,
        });

        var writer = sphtud.http.httpWriter(connection.writer());
        try writer.start(.{ .status = .ok, .content_length = response_str.len });
        try writer.writeBody(response_str);
    }

    fn respondEmpty(connection: std.net.Stream) !void {
        var writer = sphtud.http.httpWriter(connection.writer());
        try writer.start(.{ .status = .ok, .content_length = 0 });
        try writer.writeBody("");
    }
};

fn contentTypeFromExtension(path: []const u8) ?[]const u8 {
    const extension = std.fs.path.extension(path);

    const KnownExtensions = enum {
        @".html",
        @".js",
    };

    const parsed_extension = std.meta.stringToEnum(KnownExtensions, extension) orelse return null;
    return switch (parsed_extension) {
        .@".html" => "text/html",
        .@".js" => "text/javascript",
    };
}

const ConnectionGenerator = struct {
    alloc: *sphtud.alloc.Sphalloc,
    shared: *HttpContext,

    pub fn generate(self: *ConnectionGenerator, std_connection: std.net.Server.Connection) anyerror!sphtud.event.Handler {
        const connection = try sphtud.event.net.httpConnection(
            self.alloc,
            self.shared.scratch,
            std_connection.stream,
            self.shared,
        );
        return connection.handler();
    }

    pub fn close(_: *ConnectionGenerator) void {}
};

const Args = struct {
    db_path: [:0]const u8,
    address: std.net.Address,

    pub fn parse(it_const: std.process.ArgIterator) Args {
        var it = it_const;
        var ip: []const u8 = "0.0.0.0";
        var port: ?u16 = null;
        var db_path: ?[:0]const u8 = null;

        const exe = it.next() orelse "feed_me";

        const Switch = enum {
            @"--db-path",
            @"--ip",
            @"--port",
            @"--help",
        };

        while (it.next()) |arg| {
            const s = std.meta.stringToEnum(Switch, arg) orelse {
                help(exe, "Unknown argument: {s}", .{arg});
            };

            switch (s) {
                .@"--db-path" => {
                    db_path = it.next() orelse help(exe, "--db-path missing argumnet", .{});
                },
                .@"--ip" => {
                    ip = it.next() orelse help(exe, "--ip missing argument", .{});
                },
                .@"--port" => {
                    const port_string = it.next() orelse help(exe, "--port missing argumnet", .{});
                    port = std.fmt.parseInt(u16, port_string, 0) catch |e| help(exe, "invalid --port: {s}", .{@errorName(e)});
                },
                .@"--help" => {
                    help(exe, "", .{});
                },
            }
        }

        const address = std.net.Address.parseIp(ip, port orelse help(exe, "--port not provided", .{}));

        return .{
            .db_path = db_path orelse help(exe, "--db-path not provided", .{}),
            .address = address catch |e| help(exe, "Invalid address: {s}", .{@errorName(e)}),
        };
    }

    fn help(process_name: []const u8, comptime msg: []const u8, args: anytype) noreturn {
        const stderr = std.io.getStdErr();
        const writer = stderr.writer();

        const usage =
            \\{s}: [ARGS]
            \\
            \\REQUIRED:
            \\--db-path: Where to store our data
            \\--port: Which port to serve on
            \\
            \\OPTIONAL:
            \\--ip: Which ip to serve on (defaults to all)
            \\--help: Show this help
            \\
        ;

        if (msg.len != 0) {
            writer.print(msg, args) catch unreachable;
            writer.writeAll("\n\n") catch unreachable;
        }

        writer.print(usage, .{process_name}) catch unreachable;

        std.process.exit(1);
    }
};

const SignalHandlerCtx = struct {
    shutdown_requested: bool = false,

    pub fn poll(self: *SignalHandlerCtx, info: std.os.linux.signalfd_siginfo) void {
        _ = info;
        self.shutdown_requested = true;
    }

    pub fn close(self: *SignalHandlerCtx) void {
        _ = self;
    }
};

pub fn main() !void {
    var tpa = sphtud.alloc.TinyPageAllocator(100){};

    var root_alloc: sphtud.alloc.Sphalloc = undefined;
    try root_alloc.initPinned(tpa.allocator(), "root");
    defer root_alloc.deinit();

    var scratch = sphtud.alloc.ScratchAlloc.init(try root_alloc.arena().alloc(u8, 1 * 1024 * 1024));

    var args = Args.parse(
        try std.process.argsWithAllocator(root_alloc.general()),
    );

    const std_server = try args.address.listen(.{
        .reuse_port = true,
    });

    var shared = try HttpContext.init(&root_alloc, &scratch, args.db_path);
    defer shared.deinit();

    var connection_gen = ConnectionGenerator{ .alloc = &root_alloc, .shared = &shared };

    var server = try sphtud.event.net.server(std_server, &connection_gen);

    var loop = try sphtud.event.Loop.init(&root_alloc);
    defer loop.shutdown();

    try loop.register(server.handler());

    var signal_handler = try sphtud.event.signalHandler(&.{std.os.linux.SIG.INT}, SignalHandlerCtx{});
    try loop.register(signal_handler.handler());

    while (!signal_handler.ctx.shutdown_requested) {
        defer scratch.reset();

        try loop.wait(&scratch);
    }

    std.log.info("Exiting", .{});
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
