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
    arena: std.heap.ArenaAllocator,
    id: i64,
    dishes: []const MealDish,
    summary_complete: bool,
    summary: std.AutoHashMap(i64, []const u8),

    fn parse(backing_alloc: std.mem.Allocator, lexer: *json.Lexer) !Meal {
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
                .summary => summary = try data.parseArrayToKv(
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

const ResponseHolder = struct {
    var properties: ?data.Properties = null;
    var meal: ?Meal = null;
    var dishes: ?std.AutoHashMap(i64, []const u8) = null;
};

fn buildIfReady() !void {
    const properties = &(ResponseHolder.properties orelse return);
    const meal = &(ResponseHolder.meal orelse return);
    const dishes = &(ResponseHolder.dishes orelse return);

    var arena = common.makeArena();
    defer arena.deinit();

    try makeDishList(meal, dishes);
    try makeSummary(properties, meal);
    try populateDishSearch(dishes);
}


fn pushSearchResult(dish_id: i64, dish_name: []const u8, out: anytype) !void {
    var id_buf: [10]u8 = undefined;
    const dish_id_s = try std.fmt.bufPrint(&id_buf, "{d}", .{dish_id});

    try out.openTag("div");
    try out.attribute("dish-id", dish_id_s);
    try out.content(dish_name);
    try out.closeTag("div");

}

fn populateDishSearch(dishes: *const std.AutoHashMap(i64, []const u8)) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    var it = dishes.iterator();
    while (it.next()) |entry| {
        try pushSearchResult(entry.key_ptr.*, entry.value_ptr.*, &writer);
    }

    wsr.replaceElemProperty("instantiate_dish", out_buf.items, "elems");
}

fn pushMealDish(scratch: std.mem.Allocator, meal_dish: MealDish, dishes: *const std.AutoHashMap(i64, []const u8), writer: anytype) !void {

    const dish_name = dishes.get(meal_dish.dish_id) orelse return error.MissingDish;
    const meal_dish_id_s = try std.fmt.allocPrint(scratch, "{d}", .{meal_dish.id});
    const meal_dish_div_id = try std.fmt.allocPrint(scratch, "meal-dish-{d}", .{meal_dish.id});

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

fn makeDishList(meal: *const Meal, dishes: *const std.AutoHashMap(i64, []const u8)) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    for (meal.dishes) |meal_dish| {
        try pushMealDish(arena.allocator(), meal_dish, dishes, &writer);
    }

    wsr.replaceElemProperty("meal_dishes", out_buf.items, "innerHTML");
}

fn makeSummary(properties: *const data.Properties, meal: *const Meal) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const alloc = arena.allocator();

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
    ResponseHolder.meal = try Meal.parse(std.heap.wasm_allocator, &lexer);

    try buildIfReady();
}

pub export fn onMeal() void {
    common.logFailure(onMealFailable());
}

pub export fn onIngredients() void {
}

pub fn onPropertiesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    ResponseHolder.properties = try data.Properties.parse(std.heap.wasm_allocator, wsr.getInputBuffer());
    try buildIfReady();
}

pub export fn onProperties() void {
    common.logFailure(onPropertiesFailable());
}

fn onDishesFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());

    ResponseHolder.dishes = try data.parseArrayToKv("id", i64, "name", []const u8, std.heap.wasm_allocator, &lexer);
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
    common.logFailure(requestMealUpdate());
}

fn requestMealUpdate() !void {
    var scratch = common.makeArena();
    defer scratch.deinit();

    const meal = &(ResponseHolder.meal orelse return error.NoMeal);
    const url = try std.fmt.allocPrint(scratch.allocator(), "/meals/{d}", .{meal.id});

    var req = wsr.RequestFetch.init(url, "GET");
    req.addCallback("onMealUpdate");
    req.run();
}

pub fn onMealUpdateFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const new_meal = try Meal.parse(std.heap.wasm_allocator, &lexer);

    ResponseHolder.meal.?.arena.deinit();
    ResponseHolder.meal = new_meal;

    const properties = &(ResponseHolder.properties orelse return error.NoProperties);
    try makeSummary(properties, &new_meal);
}

pub export fn onMealUpdate() void {
    common.logFailure(onMealUpdateFailable());
}

pub fn onDishSearchInputFailable() !void {
    const dishes = &(ResponseHolder.dishes orelse return error.NoDishes);

    var scratch = common.makeArena();
    defer scratch.deinit();

    wsr.getSelfProperty("value");
    var it = dishes.iterator();

    var out_buf = std.ArrayList(u8).init(scratch.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    const lower_search = try std.ascii.allocLowerString(
        scratch.allocator(),
        wsr.getInputBuffer(),
    );

    while (it.next()) |entry| {
        const lower_name = try std.ascii.allocLowerString(
            scratch.allocator(),
            entry.value_ptr.*,
        );

        if (std.mem.indexOf(u8, lower_name, lower_search) != null) {
            try pushSearchResult(entry.key_ptr.*, entry.value_ptr.*, &writer);
        }
    }

    wsr.replaceSelfProperty(out_buf.items, "elems");
}

pub export fn onDishSearchInput() void {
    common.logFailure(onDishSearchInputFailable());
}

pub fn onDishSelectedFailable() !void {
    const meal = &(ResponseHolder.meal orelse return error.NoMeal);

    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getTargetAttribute("dish-id");
    const dish_id = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
    const meal_id = meal.id;

    var req = wsr.RequestFetch.init("/meal_dishes", "PUT");
    req.addBody(
        try std.json.stringifyAlloc(
            arena.allocator(),
            .{
                .dish_id = dish_id,
                .meal_id = meal_id,
            },
            .{},
        ));

    req.addCallback("onDishAdded");
    req.run();
}

pub export fn onDishSelected() void {
    common.logFailure(onDishSelectedFailable());
}

fn onDishAddedFailable() !void {
    var scratch = common.makeArena();
    defer scratch.deinit();

    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const new_dish = try MealDish.parse(&lexer);

    var out_buf = std.ArrayList(u8).init(scratch.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    const dishes = &(ResponseHolder.dishes orelse return error.NoDishes);
    try pushMealDish(scratch.allocator(), new_dish, dishes, &writer);

    wsr.appendToElem("meal_dishes", out_buf.items);
}

pub export fn onDishAdded() void {
    common.logFailure(onDishAddedFailable());
}
