const std = @import("std");
const htmlgen = @import("htmlgen.zig");
const wsr = @import("wsr.zig");

const Ingredient = struct {
    id: i64,
    name: []const u8,
    fully_entered: bool,
};

fn writeIngredient(writer: anytype, ingredient: Ingredient) !void {
    var link_buf: [4096]u8 = undefined;
    const link = try std.fmt.bufPrint(&link_buf, "/ingredient.html?id={d}", .{ingredient.id});
    try writer.openTag("a");
    try writer.attribute("href", link);

    if (!ingredient.fully_entered) {
        try writer.attribute("class", "incomplete_link");
    }

    try writer.content(ingredient.name);
    try writer.closeTag("a");

    try writer.openTag("br");
    try writer.selfClose();
}

fn tryMakeIngredientLinks() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer _ = arena.reset(.free_all);

    const parsed = try std.json.parseFromSliceLeaky(
        []Ingredient,
        arena.allocator(),
        wsr.getInputBuffer(),
        .{ .ignore_unknown_fields = true },
    );

    std.sort.pdq(Ingredient, parsed, {}, struct {
        fn f(_: void, a: Ingredient, b: Ingredient) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.f);

    var output = std.ArrayList(u8).init(arena.allocator());
    var html_writer = htmlgen.htmlWriter((output.writer()));

    for (parsed) |ingredient| {
        try writeIngredient(&html_writer, ingredient);
    }
    wsr.replaceSelfProperty(output.items, "innerHTML");

    wsr.print("{s}", .{output.items});
}

pub export fn makeIngredientLinks() void {
    tryMakeIngredientLinks() catch |e| {
        wsr.print("{s}", .{@errorName(e)});
        return;
    };
}
