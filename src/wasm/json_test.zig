const std = @import("std");
const json = @import("json.zig");
const wsr = @import("wsr.zig");

const IngredientProperty = struct {
    id: []const u8,
    ingredient_id: []const u8,
    property_id: []const u8,
    value: []const u8,

    fn parseJson(lexer: *json.Lexer) !IngredientProperty {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);

        var ret: IngredientProperty = undefined;

        const Field = std.meta.FieldEnum(IngredientProperty);

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const field = std.meta.stringToEnum(Field, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (field) {
                .id => ret.id = try lexer.nextAsString(),
                .ingredient_id => ret.ingredient_id = try lexer.nextAsString(),
                .property_id => ret.property_id = try lexer.nextAsString(),
                .value => ret.value = try lexer.nextAsString(),
            }
        }

        return ret;
    }
};

const Ingredient = struct {
    id: []const u8,
    name: []const u8,
    serving_size_g: []const u8,
    serving_size_ml: []const u8,
    serving_size_pieces: []const u8,
    properties: []IngredientProperty,

    fn parseJson(alloc: std.mem.Allocator, lexer: *json.Lexer) !Ingredient {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);

        const IngredientProps = std.meta.FieldEnum(Ingredient);

        var id: ?[]const u8 = null;
        var name: ?[]const u8 = null;
        var serving_size_g: ?[]const u8 = null;
        var serving_size_ml: ?[]const u8 = null;
        var serving_size_pieces: ?[]const u8 = null;
        var properties: std.ArrayListUnmanaged(IngredientProperty) = .{};

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(IngredientProps, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsString(),
                .name => name = try lexer.nextAsString(),
                .serving_size_g => serving_size_g = try lexer.nextAsString(),
                .serving_size_ml => serving_size_ml = try lexer.nextAsString(),
                .serving_size_pieces => serving_size_pieces = try lexer.nextAsString(),
                .properties => {
                    _ = try lexer.expectToken(.array_start);
                    while (true) {
                        const property = IngredientProperty.parseJson(lexer) catch {
                            _ = try lexer.expectToken(.array_end);
                            break;
                        };
                        try properties.append(alloc, property);
                    }
                },
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
            .serving_size_g = serving_size_g orelse return error.MissingField,
            .serving_size_ml = serving_size_ml orelse return error.MissingField,
            .serving_size_pieces = serving_size_pieces orelse return error.MissingField,
            .properties = properties.items,
        };
    }
};

pub export fn parse() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const value = Ingredient.parseJson(arena.allocator(), &lexer) catch return;
    wsr.writeStdout(value.name);
}
