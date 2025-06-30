const std = @import("std");
const common_data = @import("../data.zig");
const common = @import("../common.zig");
const json = @import("../json.zig");

pub const global = struct {
    pub var properties: ?common_data.Properties = null;
    pub var meal: ?Meal = null;
    pub var dishes: ?std.AutoHashMap(i64, []const u8) = null;
};

pub const MealDish = struct {
    id: i64,
    dish_id: i64,

    pub fn parse(lexer: *json.Lexer) !MealDish {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var dish_id: ?i64 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(MealDish), key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .dish_id => dish_id = try lexer.nextAsInt(i64),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .dish_id = dish_id orelse return error.MissingField,
        };
    }
};

const MealDishParseCtx = struct {
    pub fn parse(_: MealDishParseCtx, lexer: *json.Lexer) !MealDish {
        return MealDish.parse(lexer);
    }
};

pub const Meal = struct {
    arena: std.heap.ArenaAllocator,
    id: i64,
    dishes: []const MealDish,
    summary_complete: bool,
    summary: std.AutoHashMap(i64, []const u8),

    pub fn parse(backing_alloc: std.mem.Allocator, lexer: *json.Lexer) !Meal {
        var arena = std.heap.ArenaAllocator.init(backing_alloc);
        errdefer arena.deinit();

        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var summary_complete: ?bool = null;
        var summary: ?std.AutoHashMap(i64, []const u8) = null;
        var dishes: ?[]const MealDish = null;

        const Fields = enum {id, dishes, summary_complete, summary };
        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(Fields, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .dishes => dishes = try lexer.parseList(MealDish, MealDishParseCtx{}, arena.allocator()),
                .summary_complete => summary_complete = try lexer.nextAsBool(),
                .summary => summary = try common_data.parseArrayToKv(
                    "property_id",
                    i64,
                    "value",
                    []const u8,
                    arena.allocator(),
                    lexer,
                ),
            }
        }

        return .{
            .arena = arena,
            .id = id orelse return error.MissingField,
            .summary_complete = summary_complete orelse return error.MissingField,
            .summary = summary orelse return error.MissingField,
            .dishes = dishes orelse &.{},
        };
    }
};

pub fn onProperties(data: []const u8) !void {
    global.properties = try common_data.Properties.parse(std.heap.wasm_allocator, data);
}

pub fn onMeal(data: []const u8) !void {
    var lexer = json.Lexer.init(data);
    global.meal = try Meal.parse(std.heap.wasm_allocator, &lexer);
}

pub fn onDishes(data: []const u8) !void {
    var lexer = json.Lexer.init(data);

    global.dishes = try common_data.parseArrayToKv("id", i64, "name", []const u8, std.heap.wasm_allocator, &lexer);
}
