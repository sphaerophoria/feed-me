const std = @import("std");
const wsr = @import("wsr.zig");
const common = @import("common.zig");
const data = @import("data.zig");
const json = @import("json.zig");
const htmlgen = @import("htmlgen.zig");

extern fn markSummaryComplete(id_ptr: [*]const u8, id_len: usize) void;

const MealDish = struct {
    id: i64,
    dish_id: i64,

    fn parse(lexer: *json.Lexer) !MealDish {
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

const Meal = struct {
    dishes: []const MealDish,
    summary_complete: bool,
    summary: std.AutoHashMap(i64, []const u8),

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !Meal {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var summary_complete: ?bool = null;
        var summary: ?std.AutoHashMap(i64, []const u8) = null;
        var dishes: ?[]const MealDish = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(Meal), key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .dishes => {
                    dishes = try lexer.parseList(MealDish, MealDishParseCtx{}, alloc);
                },
                .summary_complete => summary_complete = try lexer.nextAsBool(),
                .summary => summary = try data.parseArrayToKv(
                    "property_id",
                    i64,
                    "value",
                    []const u8,
                    alloc,
                    lexer,
                ),
            }
        }

        return .{
            .summary_complete = summary_complete orelse return error.MissingField,
            .summary = summary orelse return error.MissingField,
            .dishes = dishes orelse &.{},
        };
    }
};

const ResponseHolder = struct {
    properties: ?data.Properties = null,
    meal: ?Meal = null,
    dishes: ?std.AutoHashMap(i64, []const u8) = null,

    var instance: ResponseHolder = .{};
};

fn buildIfReady() !void {
    const properties = &(ResponseHolder.instance.properties orelse return);
    const meal = &(ResponseHolder.instance.meal orelse return);
    const dishes = &(ResponseHolder.instance.dishes orelse return);

    var arena = common.makeArena();
    defer arena.deinit();

    try makeDishList(meal, dishes);
    try makeSummary(arena.allocator(), properties, meal);
}

fn makeDishList(meal: *const Meal, dishes: *const std.AutoHashMap(i64, []const u8)) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    for (meal.dishes) |meal_dish| {
        const dish_name = dishes.get(meal_dish.dish_id) orelse return error.MissingDish;
        const meal_dish_id_s = try std.fmt.allocPrint(arena.allocator(), "{d}", .{meal_dish.id});
        const meal_dish_div_id = try std.fmt.allocPrint(arena.allocator(), "meal-dish-{d}", .{meal_dish.id});

        try writer.openTag("div");
        try writer.attribute("class", "dish_header");
        try writer.attribute("id", meal_dish_div_id);

        {
            try writer.openTag("sphdelete-button");
            try writer.attribute("wsr-onevent", "click");
            try writer.attribute("wsr-generate", "onDeleteMealDish");
            try writer.attribute("meal-dish-id", meal_dish_id_s);
            try writer.attribute("deleted-div-id", meal_dish_div_id);
            try writer.closeTag("sphdelete-button");

            try writer.openTag("h2");
            try writer.content(dish_name);
            try writer.closeTag("h2");
        }

        try writer.closeTag("div");
    }

    wsr.replaceElemProperty("meal_dishes", out_buf.items, "innerHTML");
}

fn makeSummary(alloc: std.mem.Allocator, properties: *const data.Properties, meal: *const Meal) !void {
    var property_it = properties.iter(alloc);

    var html_buf = std.ArrayList(u8).init(alloc);
    var writer = htmlgen.htmlWriter(html_buf.writer());

    var margin: i32 = 0;

    while (try property_it.next()) |entry| {
        switch (entry) {
            .level => |prop| {
                try writePropSummary(prop, meal, margin, &writer);
            },
            .indent_up => |prop| {
                margin += 2;
                try writePropSummary(prop, meal, margin, &writer);
            },
            .indent_down => {
                margin -= 2;
            },
        }
    }

    wsr.replaceElemProperty("summary", html_buf.items, "innerHTML");

    if (meal.summary_complete) {
        const summary_key = "summary";
        markSummaryComplete(summary_key.ptr, summary_key.len);
    }
}

fn writePropSummary(prop: data.Properties.Iter.PropertyElem, meal: *const Meal, margin: i32, writer: anytype) !void {
    const value = meal.summary.get(prop.id) orelse return;

    var key_style_buf: [20]u8 = undefined;
    const key_style_string = try std.fmt.bufPrint(&key_style_buf, "margin-left: {d}em", .{margin});
    try writer.openTag("div");
    try writer.attribute("style", key_style_string);
    try writer.content(prop.name);
    try writer.closeTag("div");

    try writer.openTag("div");
    try writer.attribute("style", "justify-self: end; text-align: end");
    try writer.content(value);
    try writer.closeTag("div");
}

pub fn onMealFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    ResponseHolder.instance.meal = try Meal.parse(std.heap.wasm_allocator, &lexer);

    try buildIfReady();
}

pub export fn onMeal() void {
    common.logFailure(onMealFailable());
}

pub export fn onIngredients() void {
    wsr.writeStdout(wsr.getInputBuffer());
}

pub fn onPropertiesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    ResponseHolder.instance.properties = try data.Properties.parse(std.heap.wasm_allocator, wsr.getInputBuffer());
    try buildIfReady();
}

pub export fn onProperties() void {
    common.logFailure(onPropertiesFailable());
}

fn onDishesFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());

    ResponseHolder.instance.dishes = try data.parseArrayToKv("id", i64, "name", []const u8, std.heap.wasm_allocator, &lexer);
    try buildIfReady();
}

pub export fn onDishes() void {
    common.logFailure(onDishesFailable());
}

pub fn onDeleteMealDishFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfAttribute("meal-dish-id");
    const id = wsr.getInputBuffer();
    const url = try std.fmt.allocPrint(arena.allocator(), "/meal_dishes/{s}", .{id});
    var req = wsr.RequestFetch.init(url, "DELETE");
    req.addCallback("onMealDishDeleted");
    req.run();
}

pub export fn onDeleteMealDish() void {
    common.logFailure(onDeleteMealDishFailable());
}

pub export fn onMealDishDeleted() void {
    wsr.getSelfAttribute("deleted-div-id");
    wsr.replaceElemProperty(wsr.getInputBuffer(), "", "outerHTML");
    // FIXME:
    //updateSummary();
}
