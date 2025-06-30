const std = @import("std");
const wsr = @import("wsr.zig");
const common = @import("common.zig");
const json = @import("json.zig");
const htmlgen = @import("htmlgen.zig");
const data = @import("meal/data.zig");
const common_data = @import("data.zig");
const summary = @import("meal/summary.zig");
const dish_search = @import("meal/dish_search.zig");

fn buildIfReady() !void {
    const properties = &(data.global.properties orelse return);
    const meal = &(data.global.meal orelse return);
    const dishes = &(data.global.dishes orelse return);

    var arena = common.makeArena();
    defer arena.deinit();

    try makeDishList(meal, dishes);
    try summary.makeSummary(properties, meal);
    try dish_search.populateDishSearch(dishes);
}

fn pushMealDish(scratch: std.mem.Allocator, meal_dish: data.MealDish, dishes: *const std.AutoHashMap(i64, []const u8), writer: anytype) !void {
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

fn makeDishList(meal: *const data.Meal, dishes: *const std.AutoHashMap(i64, []const u8)) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    for (meal.dishes) |meal_dish| {
        try pushMealDish(arena.allocator(), meal_dish, dishes, &writer);
    }

    wsr.replaceElemProperty("meal_dishes", out_buf.items, "innerHTML");
}

pub fn onMealFailable() !void {
    try data.onMeal(wsr.getInputBuffer());
    try buildIfReady();
}

pub export fn onMeal() void {
    common.logFailure(onMealFailable());
}

pub export fn onIngredients() void {}

fn onPropertiesFailable() !void {
    try data.onProperties(wsr.getInputBuffer());
    try buildIfReady();
}

pub export fn onProperties() void {
    common.logFailure(onPropertiesFailable());
}

fn onDishesFailable() !void {
    try data.onDishes(wsr.getInputBuffer());
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

    const meal = &(data.global.meal orelse return error.NoMeal);
    const url = try std.fmt.allocPrint(scratch.allocator(), "/meals/{d}", .{meal.id});

    var req = wsr.RequestFetch.init(url, "GET");
    req.addCallback("onMealUpdate");
    req.run();
}

pub fn onMealUpdateFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const new_meal = try data.Meal.parse(std.heap.wasm_allocator, &lexer);

    data.global.meal.?.arena.deinit();
    data.global.meal = new_meal;

    const properties = &(data.global.properties orelse return error.NoProperties);
    try summary.makeSummary(properties, &new_meal);
}

pub export fn onMealUpdate() void {
    common.logFailure(onMealUpdateFailable());
}

pub export fn onDishSearchInput() void {
    common.logFailure(dish_search.onSearchInput());
}

pub export fn onDishSelected() void {
    common.logFailure(dish_search.onSearchSelect());
}

fn onDishAddedFailable() !void {
    var scratch = common.makeArena();
    defer scratch.deinit();

    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const new_dish = try data.MealDish.parse(&lexer);

    var out_buf = std.ArrayList(u8).init(scratch.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    const dishes = &(data.global.dishes orelse return error.NoDishes);
    try pushMealDish(scratch.allocator(), new_dish, dishes, &writer);

    wsr.appendToElem("meal_dishes", out_buf.items);
}

pub export fn onDishAdded() void {
    common.logFailure(onDishAddedFailable());
}
