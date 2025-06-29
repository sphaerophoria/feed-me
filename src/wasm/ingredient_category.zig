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
    pub fn parse(_: @This(), lexer: *json.Lexer) !IngredientMapping {
        return IngredientMapping.parse(lexer);
    }
};

const IngredientMapping = struct {
    id: i64,
    ingredient_id: i64,

    pub fn parse(lexer: *json.Lexer) !IngredientMapping {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var ingredient_id: ?i64 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            if (std.mem.eql(u8, key_s, "id")) {
                id = try lexer.nextAsInt(i64);
            } else if (std.mem.eql(u8, key_s, "ingredient_id")) {
                ingredient_id = try lexer.nextAsInt(i64);
            } else {
                try lexer.discardValue();
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .ingredient_id = ingredient_id orelse return error.MissingField,
        };
    }
};

const Category = struct {
    id: i64,
    name: []const u8,
    ingredients: std.ArrayList(IngredientMapping),

    fn ingredientMappingId(self: Category, ingredient_id: i64) ?i64 {
        for (self.ingredients.items) |mapping| {
            if (mapping.ingredient_id == ingredient_id) return mapping.id;
        }
        return null;
    }

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !Category {
        _ = try lexer.expectToken(.object_start);

        const JsonField = enum { id, name, mappings };

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var ingredients: ?std.ArrayList(IngredientMapping) = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(JsonField), key_s) orelse {
                try lexer.discardValue();
                continue;
            };
            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .name => name = try lexer.nextAsStringCopy(alloc),
                .mappings => ingredients = try lexer.parseListGrowable(IngredientMapping, CategoryIngredientParseCtx{}, alloc),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
            .ingredients = ingredients orelse return error.MissingField,
        };
    }
};

fn makeSearchResult(writer: anytype, ingredient: Ingredient) !void {
    var ingredient_id_buf: [10]u8 = undefined;
    const ingredient_id_s = try std.fmt.bufPrint(&ingredient_id_buf, "{d}", .{ingredient.id});

    try writer.openTag("div");
    try writer.attribute("wsr-onevent", "sphearch-selected");
    try writer.attribute("wsr-generate", "onIngredientSelected");
    try writer.attribute("ingredient-id", ingredient_id_s);
    try writer.content(ingredient.name);
    try writer.closeTag("div");
}

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

    fn ingredientFromId(id: i64) ?Ingredient {
        if (instance.ingredients == null) return null;
        const ingredients = &instance.ingredients.?;

        for (ingredients.*) |ingredient| {
            if (ingredient.id == id) return ingredient;
        }

        return null;
    }

    fn parseIngredients() !void {
        var lexer = json.Lexer.init(wsr.getInputBuffer());
        instance.ingredients = try lexer.parseList(Ingredient, IngredientParseCtx{ .alloc = std.heap.wasm_allocator }, std.heap.wasm_allocator);
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

        var arena = common.makeArena();
        defer arena.deinit();

        wsr.replaceElemProperty("category_name_edit", category.name, "value");

        var link_buf = std.ArrayList(u8).init(arena.allocator());
        var link_writer = htmlgen.htmlWriter(link_buf.writer());
        for (ingredients.*) |ingredient| {
            if (category.ingredientMappingId(ingredient.id)) |mapping_id| {
                const row_id = try std.fmt.allocPrint(arena.allocator(), "ingredient-{d}", .{ingredient.id});
                const ingredient_id_s = try std.fmt.allocPrint(arena.allocator(), "{d}", .{ingredient.id});
                const mapping_id_s = try std.fmt.allocPrint(arena.allocator(), "{d}", .{mapping_id});

                try link_writer.openTag("div");
                try link_writer.attribute("class", "ingredient_row");
                try link_writer.attribute("ingredient-id", ingredient_id_s);
                try link_writer.attribute("id", row_id);

                try link_writer.openTag("sphdelete-button");
                try link_writer.attribute("wsr-onevent", "click");
                try link_writer.attribute("wsr-generate", "requestDeleteIngredient");
                try link_writer.attribute("delete-row-id", row_id);
                try link_writer.attribute("mapping-id", mapping_id_s);
                try link_writer.closeTag("sphdelete-button");

                try link_writer.openTag("a");
                const url = try std.fmt.allocPrint(arena.allocator(), "/ingredient.html?id={d}", .{ingredient.id});
                try link_writer.attribute("href", url);
                try link_writer.content(ingredient.name);
                try link_writer.closeTag("a");

                try link_writer.closeTag("div");
            }
        }
        wsr.replaceElemProperty("ingredient_links", link_buf.items, "innerHTML");

        var search_buf = std.ArrayList(u8).init(arena.allocator());
        var search_writer = htmlgen.htmlWriter(search_buf.writer());
        for (ingredients.*) |ingredient| {
            try makeSearchResult(&search_writer, ingredient);
        }
        wsr.replaceElemProperty("add_ingredient_search", search_buf.items, "elems");
    }
};

fn makeIngredientRow(scratch: std.mem.Allocator, writer: anytype, ingredient: Ingredient, mapping_id: i64) !void {
    const row_id = try std.fmt.allocPrint(scratch, "ingredient-{d}", .{ingredient.id});
    const ingredient_id_s = try std.fmt.allocPrint(scratch, "{d}", .{ingredient.id});
    const mapping_id_s = try std.fmt.allocPrint(scratch, "{d}", .{mapping_id});

    try writer.openTag("div");
    try writer.attribute("class", "ingredient_row");
    try writer.attribute("ingredient-id", ingredient_id_s);
    try writer.attribute("id", row_id);

    try writer.openTag("sphdelete-button");
    try writer.attribute("wsr-onevent", "click");
    try writer.attribute("wsr-generate", "requestDeleteIngredient");
    try writer.attribute("delete-row-id", row_id);
    try writer.attribute("mapping-id", mapping_id_s);
    try writer.closeTag("sphdelete-button");

    try writer.openTag("a");
    const url = try std.fmt.allocPrint(scratch, "/ingredient.html?id={d}", .{ingredient.id});
    try writer.attribute("href", url);
    try writer.content(ingredient.name);
    try writer.closeTag("a");

    try writer.closeTag("div");
}

pub export fn onCategory() void {
    common.logFailure(ResponseHolder.parseCategory());
}

pub export fn onIngredients() void {
    common.logFailure(ResponseHolder.parseIngredients());
}

fn onIngredientSearchInputFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const ingredients = &ResponseHolder.instance.ingredients.?;

    wsr.getSelfProperty("value");
    const lower_search = try std.ascii.allocLowerString(arena.allocator(), wsr.getInputBuffer());

    var output_buf = std.ArrayList(u8).init(arena.allocator());
    var html_writer = htmlgen.htmlWriter(output_buf.writer());

    for (ingredients.*) |ingredient| {
        const lower_name = try std.ascii.allocLowerString(arena.allocator(), ingredient.name);
        if (std.mem.indexOf(u8, lower_name, lower_search) != null) {
            try makeSearchResult(&html_writer, ingredient);
        }
    }

    wsr.replaceElemProperty("add_ingredient_search", output_buf.items, "elems");
}

pub export fn onIngredientSearchInput() void {
    common.logFailure(onIngredientSearchInputFailable());
}

pub export fn onDeleteIngredient() void {
    wsr.getSelfAttribute("delete-row-id");
    wsr.replaceElemProperty(wsr.getInputBuffer(), "", "outerHTML");
}

pub fn requestDeleteIngredientFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfAttribute("mapping-id");

    const url = try std.fmt.allocPrint(arena.allocator(), "/ingredient_category_mappings/{s}", .{wsr.getInputBuffer()});

    var req = wsr.RequestFetch.init(url, "DELETE");
    req.addCallback("onDeleteIngredient");
    req.run();
}

pub export fn requestDeleteIngredient() void {
    common.logFailure(requestDeleteIngredientFailable());
}

pub fn onIngredientSelectedFailble() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfAttribute("ingredient-id");
    const ingredient_id: i64 = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);

    var req = wsr.RequestFetch.init("/ingredient_category_mappings", "PUT");
    req.addCallback("onIngredientAdded");
    req.addBody(try std.json.stringifyAlloc(
        arena.allocator(),
        .{
            .ingredient_id = ingredient_id,
            .category_id = ResponseHolder.instance.category.?.id,
        },
        .{},
    ));
    req.run();
}

pub export fn onIngredientSelected() void {
    common.logFailure(onIngredientSelectedFailble());
}

pub fn onIngredientAddedFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const mapping = blk: {
        var lexer = json.Lexer.init(wsr.getInputBuffer());
        break :blk try IngredientMapping.parse(&lexer);
    };

    wsr.getSelfAttribute("ingredient-id");
    const ingredient_id: i64 = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);

    const ingredient = ResponseHolder.ingredientFromId(ingredient_id) orelse return error.MissingIngredient;

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    try makeIngredientRow(arena.allocator(), &writer, ingredient, mapping.id);

    wsr.appendToElem("ingredient_links", out_buf.items);
}

pub export fn onIngredientAdded() void {
    common.logFailure(onIngredientAddedFailable());
}

pub fn onNameChangeFailable() !void {
    if (ResponseHolder.instance.category == null) {
        return;
    }
    const category = &ResponseHolder.instance.category.?;

    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfProperty("value");
    const new_name = wsr.getInputBuffer();

    const url = try std.fmt.allocPrint(arena.allocator(), "/ingredient_categories/{d}", .{category.id});
    const body = try std.json.stringifyAlloc(
        arena.allocator(),
        .{
            .name = new_name,
        },
        .{},
    );

    var req = wsr.RequestFetch.init(url, "PUT");
    req.addBody(body);
    req.run();
}

pub export fn onNameChange() void {
    common.logFailure(onNameChangeFailable());
}
