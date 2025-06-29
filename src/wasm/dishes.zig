const std = @import("std");
const wsr = @import("wsr.zig");
const json = @import("json.zig");
const common = @import("common.zig");
const htmlgen = @import("htmlgen.zig");

const Dish = struct {
    id: []const u8,
    name: []const u8,

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !Dish {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?[]const u8 = null;
        var name: ?[]const u8 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(Dish), key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsStringRef(alloc),
                .name => name = try lexer.nextAsStringRef(alloc),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
        };
    }
};
const ParseCtx = struct {
    alloc: std.mem.Allocator,

    pub fn parse(self: @This(), lexer: *json.Lexer) !Dish {
        return Dish.parse(self.alloc, lexer);
    }
};

fn parseDishNames(alloc: std.mem.Allocator) ![]const Dish {
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    return try lexer.parseList(Dish, ParseCtx{ .alloc = alloc }, alloc);
}

pub fn onDishesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const dishes = try parseDishNames(arena.allocator());
    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    for (dishes) |dish| {
        try writer.openTag("input");
        try writer.attribute("value", dish.name);
        try writer.attribute("dish-id", dish.id);
        try writer.attribute("wsr-onevent", "input");
        try writer.attribute("wsr-generate", "onDishRename");
        try writer.selfClose();
    }

    wsr.replaceSelfProperty(out_buf.items, "innerHTML");
}

pub export fn onDishes() void {
    common.logFailure(onDishesFailable());
}

pub fn onDishRenameFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfAttribute("dish-id");
    const url = try std.fmt.allocPrint(arena.allocator(), "/dishes/{s}", .{wsr.getInputBuffer()});

    wsr.getSelfProperty("value");
    const new_name = wsr.getInputBuffer();

    var req = wsr.RequestFetch.init(url, "PUT");
    req.addBody(try std.json.stringifyAlloc(
        arena.allocator(),
        .{
            .name = new_name,
        },
        .{},
    ));
    req.run();
}

pub export fn onDishRename() void {
    common.logFailure(onDishRenameFailable());
}
