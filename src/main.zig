const sphtud = @import("sphtud");
const std = @import("std");
const api = @import("api.zig");
const Db = @import("Db.zig");

const HttpContext = struct {
    response_alloc_root: *sphtud.alloc.Sphalloc,
    resource_dir: std.fs.Dir,
    scratch: *sphtud.alloc.ScratchAlloc,
    db: Db,
    // For memory tracking purposes
    root_alloc: *sphtud.alloc.Sphalloc,

    pub fn init(root_alloc: *sphtud.alloc.Sphalloc, response_alloc: *sphtud.alloc.Sphalloc, scratch: *sphtud.alloc.ScratchAlloc, db_path: [:0]const u8) !HttpContext {
        return .{
            .response_alloc_root = response_alloc,
            .resource_dir = try std.fs.cwd().openDir("res", .{}),
            .scratch = scratch,
            .db = try Db.init(db_path),
            .root_alloc = root_alloc,
        };
    }

    pub fn deinit(self: *HttpContext) void {
        self.db.deinit();
    }

    pub fn serve(self: *HttpContext, http_reader: *sphtud.http.HttpReader, connection: std.net.Stream) !sphtud.event.PollResult {
        const checkpoint = self.scratch.checkpoint();
        defer self.scratch.restore(checkpoint);

        // FIXME: Sanitize
        const target = (try http_reader.getTarget(self.scratch.allocator())).?;
        const body = http_reader.getBody();
        const parsed_target = try api.Target.parse(target, http_reader.header.?.method);

        const response_alloc = switch (parsed_target) {
            inline else => |_, t| try self.response_alloc_root.makeSubAlloc(@tagName(t)),
        };
        errdefer response_alloc.deinit();

        switch (parsed_target) {
            .add_ingredient => {
                const params = try parseJsonBody(api.AddIngredient, self.scratch.allocator(), body);
                try params.validate();

                const ingredient = try self.db.addIngredient(params.name);
                return respondJson(response_alloc, connection, ingredient);
            },
            .get_ingredients => {
                const ingredients = try self.db.getIngredients(self.scratch.allocator());
                return try respondJson(response_alloc, connection, ingredients);
            },
            .get_ingredient => |id| {
                const ingredient = try self.db.getIngredient(id, self.scratch.allocator());
                return try respondJson(response_alloc, connection, ingredient);
            },
            .modify_ingredient => |id| {
                const params = try parseJsonBody(api.ModifyIngredientParams, self.scratch.allocator(), body);
                try params.validate();

                const ingredient = try self.db.modifyIngredient(
                    self.scratch.allocator(),
                    id,
                    params,
                );
                return try respondJson(response_alloc, connection, ingredient);
            },
            .get_properties => {
                const property = try self.db.getProperties(self.scratch.allocator());
                return try respondJson(response_alloc, connection, property);
            },
            .add_property => {
                const params = try parseJsonBody(api.AddProperty, self.scratch.allocator(), body);
                try params.validate();

                const property = try self.db.addProperty(params);
                return try respondJson(response_alloc, connection, property);
            },
            .modify_property => |id| {
                const params = try parseJsonBody(api.ModifyProperty, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyProperty(id, params.name);
                return try respondEmpty(response_alloc, connection);
            },
            .add_ingredient_property => {
                const params = try parseJsonBody(api.AddIngredientPropertyParams, self.scratch.allocator(), body);

                const ingredient_property = try self.db.addIngredientProperty(params);
                return try respondJson(response_alloc, connection, ingredient_property);
            },
            .modify_ingredient_property => |id| {
                const params = try parseJsonBody(api.ModifyIngredientPropertyParams, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyIngredientProperty(id, params.value);
                return try respondEmpty(response_alloc, connection);
            },
            .delete_ingredient_property => |id| {
                try self.db.deleteIngredientProperty(id);
                return try respondEmpty(response_alloc, connection);
            },
            .add_dish => {
                const params = try parseJsonBody(api.AddModifyDishParams, self.scratch.allocator(), body);
                try params.validate();

                const dish = try self.db.addDish(params.name);
                return try respondJson(response_alloc, connection, dish);
            },
            .modify_dish => |id| {
                const params = try parseJsonBody(api.AddModifyDishParams, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyDish(id, params.name);
                return try respondEmpty(response_alloc, connection);
            },
            .get_dishes => {
                const dishes = try self.db.getDishes(self.scratch.allocator());
                return try respondJson(response_alloc, connection, dishes);
            },
            .add_meal => {
                const params = try parseJsonBody(api.AddMealParams, self.scratch.allocator(), body);

                const meal = try self.db.addMeal(params);
                return try respondJson(response_alloc, connection, meal);
            },
            .get_meals => {
                const meals = try self.db.getMeals(self.scratch.allocator(), self.scratch.backLinear());
                return try respondJson(response_alloc, connection, meals);
            },
            .get_meal => |id| {
                const meal = try self.db.getMeal(self.scratch.allocator(), self.scratch.backLinear(), id);
                return try respondJson(response_alloc, connection, meal);
            },
            .delete_meal => |id| {
                try self.db.deleteMeal(id);
                return try respondEmpty(response_alloc, connection);
            },
            .add_meal_dish => {
                const params = try parseJsonBody(api.AddMealDishParams, self.scratch.allocator(), body);
                const meal_dish = try self.db.addMealDish(params);
                return try respondJson(response_alloc, connection, meal_dish);
            },
            .delete_meal_dish => |id| {
                try self.db.deleteMealDish(id);
                return try respondEmpty(response_alloc, connection);
            },
            .add_meal_dish_ingredient => {
                const params = try parseJsonBody(api.AddMealDishIngredientParams, self.scratch.allocator(), body);
                const meal_dish_ingredient = try self.db.addMealDishIngredient(params);
                return try respondJson(response_alloc, connection, meal_dish_ingredient);
            },
            .modify_meal_dish_ingredient => |id| {
                const params = try parseJsonBody(api.ModifyMealDishIngredientParams, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyMealDishIngredient(id, params);
                return try respondEmpty(response_alloc, connection);
            },
            .add_ingredient_category => {
                const params = try parseJsonBody(api.AddIngredientCategoryParams, self.scratch.allocator(), body);
                try params.validate();

                const new_category = try self.db.addIngredientCategory(self.scratch.allocator(), params);
                return try respondJson(response_alloc, connection, new_category);
            },
            .get_ingredient_category => |id| {
                const category = try self.db.getIngredientCategory(self.scratch.allocator(), id);
                return try respondJson(response_alloc, connection, category);
            },
            .get_ingredient_categories => {
                const categories = try self.db.getIngredientCategories(self.scratch.allocator());
                return try respondJson(response_alloc, connection, categories);
            },
            .modify_ingredient_category => |id| {
                const params = try parseJsonBody(api.ModifyIngredientCategoryParams, self.scratch.allocator(), body);
                try params.validate();

                try self.db.modifyIngredientCategory(id, params);
                return try respondEmpty(response_alloc, connection);
            },
            .add_ingredient_to_category => {
                const params = try parseJsonBody(api.AddIngredientCategoryMapping, self.scratch.allocator(), body);

                const response = try self.db.addIngredientCategoryMapping(params);
                return try respondJson(response_alloc, connection, response);
            },
            .delete_ingredient_category_mapping => |id| {
                try self.db.deleteIngredientCategoryMapping(id);
                return try respondEmpty(response_alloc, connection);
            },
            .copy_meal_dish => {
                const params = try parseJsonBody(api.CopyMealDishParams, self.scratch.allocator(), body);
                const new_ingredients = try self.db.copyMealDish(self.scratch.allocator(), params);
                return try respondJson(response_alloc, connection, new_ingredients);
            },
            .delete_meal_dish_ingredient => |id| {
                try self.db.deleteMealDishIngredient(id);
                return try respondEmpty(response_alloc, connection);
            },
            .redirect_to_index => {
                const response: []const u8 = sphtud.http.makeHttpHeaderComptime(.{
                    .status = .moved_permanently,
                    .content_length = 0,
                    .headers = &.{
                        .{ .key = "Location", .value = "/index.html" },
                    },
                });
                return try respondBuffers(response_alloc, connection, &.{response});
            },
            .memory_usage => {
                var response_buf = try sphtud.util.RuntimeBoundedArray(u8).init(response_alloc.arena(), 8192);
                var w = response_buf.writer();

                const memory_snapshot = try sphtud.alloc.MemoryTracker.snapshot(self.scratch.allocator(), self.root_alloc, 100);
                try w.print("Memory usage\n", .{});
                for (memory_snapshot) |elem| {
                    try w.print("{s}: {d}\n", .{ elem.name, elem.memory_used });
                }

                const header = try sphtud.http.makeHttpHeader(response_alloc.arena(), .{
                    .status = .ok,
                    .content_length = response_buf.items.len,
                    .content_type = "text/plain",
                });
                return try respondBuffers(response_alloc, connection, &.{ header, response_buf.items });
            },
            .filesystem => |fs_path| {
                const target_end = std.mem.indexOfScalar(u8, fs_path, '?') orelse fs_path.len;
                return try respondFile(response_alloc, connection, self.resource_dir, fs_path[1..target_end]);
            },
        }
    }

    fn parseJsonBody(comptime T: type, leaky: std.mem.Allocator, body: sphtud.util.RuntimeSegmentedList(u8).Slice) !T {
        var body_reader = body.reader();
        var jw = std.json.reader(leaky, body_reader.generic());
        return try std.json.parseFromTokenSourceLeaky(T, leaky, &jw, .{});
    }

    const FinishResponse = struct {
        response_alloc: *sphtud.alloc.Sphalloc,
        connection: std.net.Stream,

        pub fn notify(self: *FinishResponse) void {
            self.connection.close();
            self.response_alloc.deinit();
        }
    };

    fn respondJson(response_alloc: *sphtud.alloc.Sphalloc, connection: std.net.Stream, response: anytype) !sphtud.event.PollResult {
        const response_body = try std.json.stringifyAlloc(response_alloc.arena(), response, .{
            .emit_null_optional_fields = false,
        });

        const header = try sphtud.http.makeHttpHeader(response_alloc.arena(), .{
            .status = .ok,
            .content_length = response_body.len,
        });

        return try respondBuffers(response_alloc, connection, &.{ header, response_body });
    }

    fn respondEmpty(alloc: *sphtud.alloc.Sphalloc, connection: std.net.Stream) !sphtud.event.PollResult {
        const response: []const u8 = sphtud.http.makeHttpHeaderComptime(.{
            .status = .ok,
            .content_length = 0,
        });

        return try respondBuffers(alloc, connection, &.{response});
    }

    fn respondBuffers(response_alloc: *sphtud.alloc.Sphalloc, connection: std.net.Stream, bufs: []const []const u8) !sphtud.event.PollResult {
        const buf_writer = try response_alloc.arena().create(sphtud.event.FdRefBufsWriter);
        buf_writer.* = try sphtud.event.FdRefBufsWriter.init(response_alloc.arena(), connection.handle, bufs);

        const handler = try sphtud.event.connectionStateMachine(
            response_alloc.arena(),
            &.{buf_writer.handler()},
            FinishResponse{
                .response_alloc = response_alloc,
                .connection = connection,
            },
        );

        return .{
            .replace_handler = handler,
        };
    }

    fn respondFile(response_alloc: *sphtud.alloc.Sphalloc, connection: std.net.Stream, dir: std.fs.Dir, path: []const u8) !sphtud.event.PollResult {
        const file = try dir.openFile(path, .{});

        const content_len = try file.getEndPos();

        const content_type = contentTypeFromExtension(path);

        const header = try sphtud.http.makeHttpHeader(response_alloc.arena(), .{
            .status = .ok,
            .content_length = content_len,
            .content_type = content_type,
        });

        const buf_writer = try response_alloc.arena().create(sphtud.event.FdRefBufsWriter);
        buf_writer.* = try sphtud.event.FdRefBufsWriter.init(response_alloc.arena(), connection.handle, &.{header});

        const send_file = try sphtud.event.SendFile.init(
            response_alloc.arena(),
            file.handle,
            connection.handle,
            content_len,
        );

        const OnFinish = struct {
            connection: std.net.Stream,
            alloc: *sphtud.alloc.Sphalloc,
            file: std.fs.File,
            name: []const u8,

            pub fn notify(ctx: @This()) void {
                ctx.file.close();
                ctx.connection.close();
                ctx.alloc.deinit();
            }
        };

        const handler = try sphtud.event.connectionStateMachine(
            response_alloc.arena(),
            &.{
                buf_writer.handler(),
                send_file.handler(),
            },
            OnFinish{
                .connection = connection,
                .alloc = response_alloc,
                .file = file,
                .name = try response_alloc.arena().dupe(u8, path),
            },
        );

        return .{
            .replace_handler = handler,
        };
    }
};

fn contentTypeFromExtension(path: []const u8) ?[]const u8 {
    const extension = std.fs.path.extension(path);

    const KnownExtensions = enum {
        @".html",
        @".js",
        @".svg",
    };

    const parsed_extension = std.meta.stringToEnum(KnownExtensions, extension) orelse return null;
    return switch (parsed_extension) {
        .@".html" => "text/html",
        .@".js" => "text/javascript",
        .@".svg" => "image/svg+xml",
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

    var shared = try HttpContext.init(&root_alloc, try root_alloc.makeSubAlloc("http response"), &scratch, args.db_path);
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
