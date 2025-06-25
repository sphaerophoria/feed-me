const std = @import("std");
const wsr = @import("wasm/wsr.zig");

const Ingredient = struct {
    id: []const u8,
    name: []const u8,
    serving_size_g: []const u8,
    serving_size_ml: []const u8,
    serving_size_pieces: []const u8,
    properties: []IngredientProperty,
};

const IngredientProperty = struct {
    id: []const u8,
    ingredient_id: []const u8,
    property_id: []const u8,
    value: []const u8,
};

pub export fn parse() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    const value = std.json.parseFromSliceLeaky(Ingredient, arena.allocator(), wsr.getInputBuffer(), .{.ignore_unknown_fields = true});
    wsr.print("{any}", .{value});
}
