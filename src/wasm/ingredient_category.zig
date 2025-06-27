const std = @import("std");
const wsr = @import("wsr.zig");
const json = @import("json.zig");
const common = @import("common.zig");
const htmlgen = @import("htmlgen.zig");

const Ingredient = struct {
    id: i64,
    name: []const u8,

    fn parseIngredient(alloc: std.mem.Allocator, lexer: *json.Lexer) !Ingredient {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(Ingredient), key_s) orelse {
                try lexer.discardValue();
                continue;
            };
            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .name => name = try lexer.nextAsStringCopy(alloc),

            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
        };
    }
};

const CategoryIngredientParseCtx = struct {
    pub fn parse(_: @This(), lexer: *json.Lexer) !i64 {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);
        var ret: ?i64 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            if (std.mem.eql(u8, key_s, "ingredient_id")) {
                ret = try lexer.nextAsInt(i64);
            } else {
                try lexer.discardValue();
            }
        }

        return ret orelse error.MissingField;
    }
};

const Category = struct {
    name: []const u8,
    ingredients: std.ArrayList(i64),

    fn hasIngredient(self: Category, ingredient_id: i64) bool {
        for (self.ingredients.items) |id| {
            if (id == ingredient_id) return true;
        }
        return false;
    }

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !Category {
        _ = try lexer.expectToken(.object_start);

        const JsonField = enum { name, mappings };

        var name: ?[]const u8 = null;
        var ingredients: ?std.ArrayList(i64) = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(JsonField), key_s) orelse {
                try lexer.discardValue();
                continue;
            };
            switch (key) {
                .name => name = try lexer.nextAsStringCopy(alloc),
                .mappings => ingredients = try lexer.parseListGrowable(i64, CategoryIngredientParseCtx{}, alloc),
            }
        }

        return .{
            .name = name orelse return error.MissingField,
            .ingredients = ingredients orelse return error.MissingField,
        };

    }
};

const ResponseHolder = struct {
    category: ?Category = null,
    ingredients: ?[]Ingredient = null,

    var instance: ResponseHolder = .{};

    const IngredientParseCtx = struct {
        alloc: std.mem.Allocator,

        pub fn parse(self: @This(), lexer: *json.Lexer) !Ingredient {
            return Ingredient.parseIngredient(self.alloc, lexer);
        }
    };
    fn parseIngredients() !void {
        var lexer = json.Lexer.init(wsr.getInputBuffer());
        instance.ingredients = try lexer.parseList(Ingredient, IngredientParseCtx{.alloc = std.heap.wasm_allocator}, std.heap.wasm_allocator);
        try buildIfReady();
    }

    fn parseCategory() !void {
        var lexer = json.Lexer.init(wsr.getInputBuffer());
        instance.category = try Category.parse(std.heap.wasm_allocator, &lexer);
        try buildIfReady();
    }

    fn buildIfReady() !void {
        if (instance.category == null) return;
        if (instance.ingredients == null) return;

        const ingredients = &instance.ingredients.?;
        const category = &instance.category.?;

        wsr.replaceElemProperty("category_name_edit", category.name, "value");

        var arena = common.makeArena();
        defer arena.deinit();

        var link_buf = std.ArrayList(u8).init(arena.allocator());
        var link_writer = htmlgen.htmlWriter(link_buf.writer());
        for (ingredients.*) |ingredient| {
            if (category.hasIngredient(ingredient.id)) {
                try link_writer.openTag("a");
                const url = try std.fmt.allocPrint(arena.allocator(), "/ingredient.html?id={d}", .{ingredient.id});
                try link_writer.attribute("href", url);
                try link_writer.content(ingredient.name);
                try link_writer.closeTag("a");

                try link_writer.openTag("br");
                try link_writer.selfClose();
            }
        }

        wsr.replaceElemProperty("ingredient_links", link_buf.items, "innerHTML");
    }
};

pub export fn onCategory() void {
    common.logFailure(ResponseHolder.parseCategory());
}

pub export fn onIngredients() void {
    common.logFailure(ResponseHolder.parseIngredients());
}
