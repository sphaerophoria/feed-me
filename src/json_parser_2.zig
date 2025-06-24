const std = @import("std");
const wsr = @import("wasm/wsr.zig");

const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: f32,
    serving_size_ml: f32,
    serving_size_pieces: f32,
    properties: []IngredientProperty,
};

const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    value: f32,
};

pub export fn parse() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    const value = std.json.parseFromSliceLeaky(Ingredient, arena.allocator(), wsr.getInputBuffer(), .{.ignore_unknown_fields = true});
    wsr.print("{any}", .{value});
}
