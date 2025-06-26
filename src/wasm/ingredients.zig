const std = @import("std");
const sphtud = @import("sphtud");
const htmlgen = @import("htmlgen.zig");
const wsr = @import("wsr.zig");
const common = @import("common.zig");
const json = @import("json.zig");
const wsrErr = wsr.attachWsrError;

pub const panic = wsr.panic;

const Ingredient = struct {
    id: i64,
    name: []const u8,
    fully_entered: bool,
    in_any_category: bool,

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !Ingredient {
        const lcp = lexer.checkpoint();
        errdefer lexer.restore(lcp);

        _ = try wsrErr(lexer.expectToken(.object_start));

        const Fields = enum { id, name, fully_entered, category_mappings };

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var fully_entered: ?bool = null;
        var in_any_category: bool = false;

        while (try wsrErr(lexer.objectKeyOrEnd())) |key_s| {
            const key = std.meta.stringToEnum(Fields, key_s) orelse {
                try wsrErr(lexer.discardValue());
                continue;
            };

            switch (key) {
                .id => id = try wsrErr(lexer.nextAsInt(i64)),
                .name => name = try wsrErr(lexer.nextAsStringCopy(alloc)),
                .fully_entered => fully_entered = try wsrErr(lexer.nextAsBool()),
                .category_mappings => in_any_category = try arrayNotEmpty(lexer),
            }
        }

        return .{
            .id = id orelse return wsr.attachWsrError(error.MissingField),
            .name = name orelse return wsr.attachWsrError(error.MissingField),
            .fully_entered = fully_entered orelse return wsr.attachWsrError(error.MissingField),
            .in_any_category = in_any_category,
        };
    }

    fn arrayNotEmpty(lexer: *json.Lexer) !bool {
        _ = try lexer.expectToken(.array_start);

        var is_empty: bool = true;
        while (true) {
            const lcp = lexer.checkpoint();
            const token = lexer.next() orelse return wsrErr(error.NoArrayEnd);
            switch (token.token_type) {
                .array_end => return !is_empty,
                .array_start, .object_start => {
                    lexer.restore(lcp);
                    try wsrErr(lexer.discardValue());
                    is_empty = false;
                },
                else => {
                    is_empty = false;
                }
            }
        }
    }
};


const IngredientCategory = struct {
    id: i64,
    name: []const u8,
    fully_entered: bool,

    fn parse(alloc: std.mem.Allocator, lexer: *json.Lexer) !IngredientCategory {
        const lcp = lexer.checkpoint();
        errdefer lexer.restore(lcp);

        _ = try lexer.expectToken(.object_start);

        const Fields = std.meta.FieldEnum(IngredientCategory);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var fully_entered: ?bool = null;

        while (try wsrErr(lexer.objectKeyOrEnd())) |key_s| {
            const key = std.meta.stringToEnum(Fields, key_s) orelse {
                try wsrErr(lexer.discardValue());
                continue;
            };

            switch (key) {
                .id => id = try wsrErr(lexer.nextAsInt(i64)),
                .name => name = try wsrErr(lexer.nextAsStringCopy(alloc)),
                .fully_entered => fully_entered = try wsrErr(lexer.nextAsBool()),
            }
        }

        return .{
            .id = id orelse return wsrErr(error.MissingField),
            .name = name orelse return wsrErr(error.MissingField),
            .fully_entered = fully_entered orelse return wsrErr(error.MissingField),
        };
    }
};

const ResponseHolder = struct {
    ingredients: ?[]Ingredient = null,
    categories: ?[]IngredientCategory = null,

    var instance: ResponseHolder = .{};
};

const Link = struct {
    name: []const u8,
    link_content: []const u8,
    fully_entered: bool,

    fn write(self: Link, writer: anytype) !void {
        try writer.openTag("a");
        try writer.attribute("href", self.link_content);

        if (!self.fully_entered) {
            try writer.attribute("class", "incomplete_link");
        }

        try writer.content(self.name);
        try writer.closeTag("a");

        try writer.openTag("br");
        try writer.selfClose();
    }
};

fn buildIfReady() !void {
    inline for (std.meta.fields(ResponseHolder)) |field| {
        if (@field(ResponseHolder.instance, field.name) == null) return;
    }

    var arena = common.makeArena();
    defer arena.deinit();

    const ingredients = &ResponseHolder.instance.ingredients.?;
    const categories = &ResponseHolder.instance.categories.?;

    var links = try wsrErr(sphtud.util.RuntimeBoundedArray(Link).init(arena.allocator(), ingredients.len + categories.len));
    for (ingredients.*) |ingredient| {
        if (!ingredient.in_any_category) {
            try wsrErr(links.append(.{
                .name = ingredient.name,
                .link_content = try wsrErr(std.fmt.allocPrint(arena.allocator(), "/ingredient.html?id={d}", .{ingredient.id})),
                .fully_entered = ingredient.fully_entered,
            }));
        }
    }

    for (categories.*) |category| {
        try wsrErr(links.append(.{
            .name = category.name,
            .link_content = try wsrErr(std.fmt.allocPrint(arena.allocator(), "/ingredient_category.html?id={d}", .{category.id})),
            .fully_entered = category.fully_entered,
        }));
    }

    std.mem.sort(Link, links.items, {}, struct {
        fn f(_: void, a: Link, b: Link) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.f);

    var output = std.ArrayList(u8).init(arena.allocator());
    var html_writer = htmlgen.htmlWriter((output.writer()));

    for (links.items) |link| {
        try wsrErr(link.write(&html_writer));
    }

    wsr.replaceElemProperty("ingredient_list", output.items, "innerHTML");
}

fn parseIngredients() ![]Ingredient {
    const ParseCtx = struct {
        pub fn parse(_: @This(), lexer: *json.Lexer) !Ingredient {
            return Ingredient.parse(std.heap.wasm_allocator, lexer);
        }
    };
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    return try wsrErr(lexer.parseList(Ingredient, ParseCtx{}, std.heap.wasm_allocator));
}

fn onIngredientsFailable() !void {
    ResponseHolder.instance.ingredients = try parseIngredients();
    try buildIfReady();
}

pub export fn onIngredients() void {
    common.logFailure(onIngredientsFailable());
}

fn parseCategories() ![]IngredientCategory {
    const ParseCtx = struct {
        pub fn parse(_: @This(), lexer: *json.Lexer) !IngredientCategory {
            return IngredientCategory.parse(std.heap.wasm_allocator, lexer);
        }
    };
    var lexer = json.Lexer.init(wsr.getInputBuffer());
    return try wsrErr(lexer.parseList(IngredientCategory, ParseCtx{}, std.heap.wasm_allocator));
}

fn onCategoriesFailable() !void {
    ResponseHolder.instance.categories = try parseCategories();
    try buildIfReady();
}

pub export fn onCategories() void {
    common.logFailure(onCategoriesFailable());
}

const AddIngredientReq = struct {
    name: []const u8,
};

fn reqNewIngredient() !void {
    wsr.getElemProperty("ingredient_name", "value");

    var arena = common.makeArena();
    defer arena.deinit();

    var req = wsr.RequestFetch.init("/ingredients", "PUT");
    req.addBody(try std.json.stringifyAlloc(arena.allocator(), AddIngredientReq{
        .name = wsr.getInputBuffer(),
    }, .{}));
    req.addCallback("onIngredientAdded");
    req.run();
}

pub export fn onNewInput() void {
    wsr.getEventProperty("key");
    if (std.mem.eql(u8, wsr.getInputBuffer(), "Enter")) {
        common.logFailure(wsrErr(reqNewIngredient()));
    }
}

fn onIngredientAddedFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var lexer = json.Lexer.init(wsr.getInputBuffer());
    const new_ingredient = try wsrErr(Ingredient.parse(arena.allocator(), &lexer));

    var link = Link {
        .link_content = try wsrErr(std.fmt.allocPrint(arena.allocator(), "/ingredient.html?id={d}", .{new_ingredient.id})),
        .fully_entered = false,
        .name = new_ingredient.name,
    };
    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var html_writer = htmlgen.htmlWriter(out_buf.writer());
    try wsrErr(link.write(&html_writer));
    wsr.appendToElem("ingredient_list", out_buf.items);

    wsr.replaceElemProperty("ingredient_name", "", "value");
}

pub export fn onIngredientAdded() void {
    common.logFailure(onIngredientAddedFailable());
}

pub export fn onAddClicked() void {
    common.logFailure(wsrErr(reqNewIngredient()));
}
