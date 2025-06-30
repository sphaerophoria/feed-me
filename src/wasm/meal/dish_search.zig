const std = @import("std");
const common = @import("../common.zig");
const htmlgen = @import("../htmlgen.zig");
const wsr = @import("../wsr.zig");
const data = @import("data.zig");

pub fn populateDishSearch(dishes: *const std.AutoHashMap(i64, []const u8)) !void {
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

pub fn onSearchInput() !void {
    const dishes = &(data.global.dishes orelse return error.NoDishes);

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

pub fn onSearchSelect() !void {
    const meal = &(data.global.meal orelse return error.NoMeal);

    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getTargetAttribute("dish-id");
    const dish_id = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
    const meal_id = meal.id;

    var req = wsr.RequestFetch.init("/meal_dishes", "PUT");
    req.addBody(try std.json.stringifyAlloc(
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

fn pushSearchResult(dish_id: i64, dish_name: []const u8, out: anytype) !void {
    var id_buf: [10]u8 = undefined;
    const dish_id_s = try std.fmt.bufPrint(&id_buf, "{d}", .{dish_id});

    try out.openTag("div");
    try out.attribute("dish-id", dish_id_s);
    try out.content(dish_name);
    try out.closeTag("div");
}
