const std = @import("std");
const wsr = @import("wsr.zig");
const htmlgen = @import("htmlgen.zig");
const json = @import("json.zig");
const common = @import("common.zig");

pub const panic = wsr.panic;
pub const returnErrorHook = wsr.returnErrorHook;

extern fn focusWidget(key_ptr: [*]const u8, key_len: usize) void;

fn numberString(alloc: std.mem.Allocator, num: anytype) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d}", .{num});
}

const IngredientCategory = struct {
    id: i64,
    name: []const u8,

    fn parseJson(alloc: std.mem.Allocator, lexer: *json.Lexer) !IngredientCategory {
        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(IngredientCategory), key_s) orelse {
                _ = try lexer.discardValue();
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

const PageBuilder = struct {
    ingredient: ?Ingredient = null,
    properties: ?[]Property = null,
    category_names: ?std.AutoHashMap(i64, []const u8) = null,

    var instance: PageBuilder = .{};

    fn getInstance() !*PageBuilder {
        return &instance;
    }

    fn handleCategoriesResponse() !void {
        const self = try getInstance();
        if (self.category_names != null) return error.AlreadyInitialized;

        var ret = std.AutoHashMap(i64, []const u8).init(std.heap.wasm_allocator);

        var lexer = json.Lexer.init(wsr.getInputBuffer());
        _ = try lexer.expectToken(.array_start);

        while (true) {
            const cp = lexer.checkpoint();
            const token = lexer.next() orelse return error.IncompleteItem;
            switch (token.token_type) {
                .array_end => break,
                .object_start => {
                    lexer.restore(cp);

                    const category = try IngredientCategory.parseJson(std.heap.wasm_allocator, &lexer);
                    try ret.put(category.id, category.name);
                },
                else => return error.UnexpectedToken,
            }
        }
        self.category_names = ret;
        try self.buildIfReady();
    }

    fn handlePropertiesResponse() !void {
        const self = try getInstance();
        if (self.properties != null) return error.AlreadyInitialized;

        const ParseCtx = struct {
            pub fn parse(_: @This(), l: *json.Lexer) !Property {
                return Property.parseJson(std.heap.wasm_allocator, l);
            }
        };

        var lexer = json.Lexer.init(wsr.getInputBuffer());
        self.properties = try lexer.parseList(Property, ParseCtx{}, std.heap.wasm_allocator);
        try self.buildIfReady();
    }

    fn handleIngredientResponse() !void {
        const self = try getInstance();
        if (self.ingredient != null) return error.AlreadyInitialized;

        var lexer = json.Lexer.init(wsr.getInputBuffer());
        self.ingredient = try Ingredient.parseJson(std.heap.wasm_allocator, &lexer);
        try self.buildIfReady();
    }

    fn buildIfReady(self: *PageBuilder) !void {
        const ingredient = self.ingredient orelse return;
        const properties = self.properties orelse return;
        const category_names = self.category_names orelse return;
        Page.instance = .{
            .ingredient = ingredient,
            .properties = properties,
            .category_names = category_names,
        };
        try Page.instance.?.makeIngredientContent();
    }
};

fn boolString(val: bool) []const u8 {
    if (val) return "true" else return "false";
}

const Page = struct {
    ingredient: Ingredient,
    properties: []Property,
    category_names: std.AutoHashMap(i64, []const u8),

    var instance: ?Page = null;

    fn getInstance() !*Page {
        if (instance == null) {
            return error.Uninitialized;
        }
        return &instance.?;
    }

    fn replacePromoteButton(self: *Page, scratch: std.mem.Allocator) !void {
        var categories_buf = std.ArrayList(u8).init(scratch);
        var categories_writer = htmlgen.htmlWriter(categories_buf.writer());

        try categories_writer.openTag("h2");
        try categories_writer.content("Categories");
        try categories_writer.closeTag("h2");

        for (self.ingredient.category_mappings.items) |category_id| {
            const name = self.category_names.get(category_id) orelse continue;

            const url = try std.fmt.allocPrint(scratch, "/ingredient_category.html?id={d}", .{category_id});
            try categories_writer.openTag("a");
            try categories_writer.attribute("href", url);
            try categories_writer.content(name);
            try categories_writer.closeTag("a");
        }

        wsr.replaceElemProperty("category_block", categories_buf.items, "innerHTML");
    }

    fn makeIngredientContent(self: *Page) !void {
        var arena = common.makeArena();
        defer arena.deinit();

        wsr.replaceElemProperty("title", self.ingredient.name, "value");

        if (self.ingredient.category_mappings.items.len > 0) {
            try self.replacePromoteButton(arena.allocator());
        }

        wsr.replaceElemPropertyInt("complete_checkbox", @intFromBool(self.ingredient.fully_entered), "checked");

        const serving_size_g_text = try numberString(arena.allocator(), self.ingredient.serving_size_g);
        wsr.replaceElemProperty("serving_size_g", serving_size_g_text, "value");

        const serving_size_ml_text = try numberString(arena.allocator(), self.ingredient.serving_size_ml);
        wsr.replaceElemProperty("serving_size_ml", serving_size_ml_text, "value");

        const serving_size_pieces_text = try numberString(arena.allocator(), self.ingredient.serving_size_pieces);
        wsr.replaceElemProperty("serving_size_pieces", serving_size_pieces_text, "value");

        var property_buf = std.ArrayList(u8).init(arena.allocator());
        try property_buf.ensureTotalCapacity(4096);

        var html_writer = htmlgen.htmlWriter(property_buf.writer());
        for (self.ingredient.properties) |ingredient_property| {
            _ = try self.writeProperty(arena.allocator(), &html_writer, ingredient_property);
        }

        wsr.replaceElemProperty("ingredient_properties", property_buf.items, "innerHTML");

        {
            var search_result_buf = std.ArrayList(u8).init(arena.allocator());
            var search_result_writer = htmlgen.htmlWriter(search_result_buf.writer());

            for (self.properties) |property| {
                try writeSearchResult(arena.allocator(), &search_result_writer, property);
            }

            wsr.replaceElemProperty("new_property", search_result_buf.items, "elems");
        }
    }

    fn writeProperty(self: *Page, scratch: std.mem.Allocator, html_writer: anytype, ingredient_property: IngredientProperty) ![]const u8 {
        const property = self.propertyById(ingredient_property.property_id) orelse {
            wsr.print("ERROR: Missing property id: {d}", .{ingredient_property.property_id});
            return &.{};
        };

        const ingredient_property_id_string = try numberString(scratch, ingredient_property.id);

        const id_prop = try std.fmt.allocPrint(
            scratch,
            "ingredient-property-{d}",
            .{ingredient_property.id},
        );
        try html_writer.openTag("div");
        try html_writer.attribute("class", "ingredient_row");
        try html_writer.attribute("id", id_prop);

        try html_writer.openTag("sphdelete-button");
        try html_writer.attribute("wsr-onevent", "click");
        try html_writer.attribute("wsr-generate", "requestPropertyDelete");
        try html_writer.attribute("ingredient-property-id", ingredient_property_id_string);
        try html_writer.attribute("delete-id", id_prop);
        try html_writer.closeTag("sphdelete-button");

        try html_writer.openTag("label");
        try html_writer.attribute("class", "ingredient_label");
        try html_writer.content(property.name);
        try html_writer.closeTag("label");

        try html_writer.openTag("input");
        const input_id = try std.fmt.allocPrint(scratch, "property-input-{d}", .{ingredient_property.id});
        try html_writer.attribute("id", input_id);
        try html_writer.attribute("wsr-onevent", "keyup");
        try html_writer.attribute("wsr-generate", "onPropertyValueChange");
        try html_writer.attribute("ingredient-property-id", ingredient_property_id_string);
        try html_writer.attribute("type", "number");

        try html_writer.attribute("value", ingredient_property.value);
        try html_writer.selfClose();
        try html_writer.closeTag("div");

        return input_id;
    }

    fn writeSearchResult(scratch: std.mem.Allocator, writer: anytype, property: Property) !void {
        try writer.openTag("div");
        try writer.attribute("wsr-onevent", "sphearch-selected");
        try writer.attribute("wsr-generate", "onAddPropertySelect");
        try writer.attribute("property-id", try numberString(scratch, property.id));
        try writer.content(property.name);
        try writer.closeTag("div");
    }

    fn servingSizeGChanged(self: *Page) !void {
        var arena = common.makeArena();
        defer arena.deinit();

        const new_size = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
        const body = try std.json.stringifyAlloc(arena.allocator(), IngredientModificationReq{
            .serving_size_g = new_size,
        }, .{});

        const put_url = try std.fmt.allocPrint(arena.allocator(), "/ingredients/{d}", .{self.ingredient.id});
        wsr.requestPut(put_url, body);
    }

    fn handleComponentChanged(comptime name: []const u8, val: anytype) !void {
        const self = try getInstance();
        var arena = common.makeArena();
        defer arena.deinit();

        var req = IngredientModificationReq{};
        @field(req, name) = val;

        const body = try std.json.stringifyAlloc(
            arena.allocator(),
            req,
            .{ .emit_null_optional_fields = false },
        );

        const put_url = try std.fmt.allocPrint(
            arena.allocator(),
            "/ingredients/{d}",
            .{self.ingredient.id},
        );
        wsr.requestPut(put_url, body);
    }

    fn propertyById(self: Page, id: i64) ?Property {
        // FIXME: HashMap
        for (self.properties) |prop| {
            if (prop.id == id) return prop;
        }
        return null;
    }

    fn onPropertyValueChange() !void {
        var arena = common.makeArena();
        defer arena.deinit();

        wsr.getEventProperty("key");
        if (std.mem.eql(u8, wsr.getInputBuffer(), "Enter")) {
            const new_property_id = "new_property";
            focusWidget(new_property_id, new_property_id.len);
        }

        // FIXME: Do we still need all these argument types?
        wsr.getSelfAttribute("ingredient-property-id");
        const id_s = try arena.allocator().dupe(u8, wsr.getInputBuffer());

        wsr.getSelfProperty("value");
        const value_s = wsr.getInputBuffer();

        if (value_s.len == 0) {
            return;
        }
        const url = try std.fmt.allocPrint(arena.allocator(), "/ingredient_properties/{s}", .{id_s});
        const body = try std.json.stringifyAlloc(
            arena.allocator(),
            IngredientPropertyMod{
                .value = value_s,
            },
            .{},
        );

        var req = wsr.RequestFetch.init(url, "PUT");
        req.addBody(body);
        req.run();
    }

    fn onPromoteClicked() !void {
        const self = try getInstance();
        var arena = common.makeArena();
        defer arena.deinit();

        var req = wsr.RequestFetch.init("/ingredient_categories", "PUT");
        const body = try std.json.stringifyAlloc(
            arena.allocator(),
            .{
                .ingredient_id = self.ingredient.id,
            },
            .{},
        );
        req.addBody(body);
        req.addCallback("onPromoteComplete");
        req.run();
    }

    fn onPromoteComplete() !void {
        const self = try getInstance();
        var lexer = json.Lexer.init(wsr.getInputBuffer());

        const new_category = try IngredientCategory.parseJson(std.heap.wasm_allocator, &lexer);
        try self.ingredient.category_mappings.append(new_category.id);
        try self.category_names.put(new_category.id, new_category.name);

        var arena = common.makeArena();
        defer arena.deinit();
        try self.replacePromoteButton(arena.allocator());
    }

    fn onAddPropertySelect() !void {
        var arena = common.makeArena();
        defer arena.deinit();

        const self = try getInstance();

        wsr.getSelfAttribute("property-id");
        const property_id = std.fmt.parseInt(i64, wsr.getInputBuffer(), 0) catch -1;

        var req = wsr.RequestFetch.init("/ingredient_properties", "PUT");
        req.addBody(try std.json.stringifyAlloc(
            arena.allocator(),
            .{
                .ingredient_id = self.ingredient.id,
                .property_id = property_id,
            },
            .{},
        ));
        req.addCallback("onPropertyAdded");
        req.run();
    }

    fn onPropertyAdded() !void {
        const self = try getInstance();
        var lexer = json.Lexer.init(wsr.getInputBuffer());

        var arena = common.makeArena();
        defer arena.deinit();

        const new_prop = try IngredientProperty.parseJson(arena.allocator(), &lexer);

        var out_buf = std.ArrayList(u8).init(arena.allocator());
        var html_writer = htmlgen.htmlWriter(out_buf.writer());
        const input_id = try self.writeProperty(arena.allocator(), &html_writer, new_prop);

        wsr.appendToElem("ingredient_properties", out_buf.items);
        wsr.replaceElemProperty("new_property", "", "value");
        focusWidget(input_id.ptr, input_id.len);
    }

    fn onPropertySearchInput() !void {
        const self = try getInstance();
        var arena = common.makeArena();
        defer arena.deinit();

        wsr.getSelfProperty("value");

        const search_string = try std.ascii.allocLowerString(arena.allocator(), wsr.getInputBuffer());

        var out_buf = std.ArrayList(u8).init(arena.allocator());
        var html_writer = htmlgen.htmlWriter(out_buf.writer());
        for (self.properties) |property| {
            const name_lower = try std.ascii.allocLowerString(arena.allocator(), property.name);
            if (search_string.len == 0 or std.mem.indexOf(u8, name_lower, search_string) != null) {
                try writeSearchResult(arena.allocator(), &html_writer, property);
            }
        }

        wsr.replaceSelfProperty(out_buf.items, "elems");
    }
};

const IngredientCategoryIdParseCtx = struct {
    pub fn parse(_: @This(), lexer: *json.Lexer) !i64 {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);

        var ret: ?i64 = null;
        while (try lexer.objectKeyOrEnd()) |key_s| {
            if (std.mem.eql(u8, key_s, "ingredient_category_id")) {
                ret = try lexer.nextAsInt(i64);
            } else {
                try lexer.discardValue();
            }
        }

        return ret orelse error.NoId;
    }
};

const IngredientPropertyParseCtx = struct {
    alloc: std.mem.Allocator,

    pub fn parse(self: @This(), lexer: *json.Lexer) !IngredientProperty {
        return IngredientProperty.parseJson(self.alloc, lexer);
    }
};

// FIXME: Share with ingredients page
const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: i64,
    serving_size_ml: i64,
    serving_size_pieces: i64,
    category_mappings: std.ArrayList(i64),
    properties: []IngredientProperty,
    fully_entered: bool,

    fn parseJson(alloc: std.mem.Allocator, lexer: *json.Lexer) !Ingredient {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);
        const Field = std.meta.FieldEnum(Ingredient);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var serving_size_g: ?i64 = null;
        var serving_size_ml: ?i64 = null;
        var serving_size_pieces: ?i64 = null;
        var properties: []IngredientProperty = &.{};
        var category_mappings = std.ArrayList(i64).init(alloc);
        var fully_entered: ?bool = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(Field, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .name => name = try alloc.dupe(u8, try lexer.nextAsString()),
                .serving_size_g => serving_size_g = try lexer.nextAsInt(i64),
                .serving_size_ml => serving_size_ml = try lexer.nextAsInt(i64),
                .serving_size_pieces => serving_size_pieces = try lexer.nextAsInt(i64),
                .category_mappings => {
                    category_mappings = try lexer.parseListGrowable(i64, IngredientCategoryIdParseCtx{}, alloc);
                },
                .properties => {
                    properties = try lexer.parseList(IngredientProperty, IngredientPropertyParseCtx{ .alloc = alloc }, alloc);
                },
                .fully_entered => fully_entered = try lexer.nextAsBool(),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
            .serving_size_g = serving_size_g orelse return error.MissingField,
            .serving_size_ml = serving_size_ml orelse return error.MissingField,
            .serving_size_pieces = serving_size_pieces orelse return error.MissingField,
            .properties = properties,
            .category_mappings = category_mappings,
            .fully_entered = fully_entered orelse return error.MissingField,
        };
    }
};

const Property = struct {
    id: i64,
    name: []const u8,

    fn parseJson(alloc: std.mem.Allocator, lexer: *json.Lexer) !Property {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);
        const Field = std.meta.FieldEnum(Property);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(Field, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .name => name = try alloc.dupe(u8, try lexer.nextAsString()),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
        };
    }
};

const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    // abc.def
    value: []const u8,

    fn parseJson(alloc: std.mem.Allocator, lexer: *json.Lexer) !IngredientProperty {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);
        const Field = std.meta.FieldEnum(IngredientProperty);

        var id: ?i64 = null;
        var ingredient_id: ?i64 = null;
        var property_id: ?i64 = null;
        var value: ?[]const u8 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(Field, key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .ingredient_id => ingredient_id = try lexer.nextAsInt(i64),
                .property_id => property_id = try lexer.nextAsInt(i64),
                .value => {
                    // Always of form abc.def due to FixedPointNumber
                    // serialization on the server
                    const tmp = try lexer.nextAsString();
                    var end_idx = tmp.len;
                    while (tmp[end_idx - 1] == '0') {
                        end_idx -= 1;
                    }
                    if (tmp[end_idx - 1] == '.') {
                        end_idx -= 1;
                    }
                    value = try alloc.dupe(u8, tmp[0..end_idx]);
                },
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .ingredient_id = ingredient_id orelse return error.MissingField,
            .property_id = property_id orelse return error.MissingField,
            .value = value orelse return error.MissingField,
        };
    }
};

const IngredientPropertyMod = struct {
    // FIXME: FixedPointNum
    value: []const u8,
};

const IngredientModificationReq = struct {
    serving_size_g: ?[]const u8 = null,
    serving_size_ml: ?[]const u8 = null,
    serving_size_pieces: ?[]const u8 = null,
    fully_entered: ?bool = null,
};

pub export fn servingSizeGChanged() void {
    wsr.getSelfProperty("value");
    common.logFailure(Page.handleComponentChanged("serving_size_g", wsr.getInputBuffer()));
}

pub export fn servingSizeMlChanged() void {
    wsr.getSelfProperty("value");
    common.logFailure(Page.handleComponentChanged("serving_size_ml", wsr.getInputBuffer()));
}

pub export fn servingSizePiecesChanged() void {
    wsr.getSelfProperty("value");
    common.logFailure(Page.handleComponentChanged("serving_size_pieces", wsr.getInputBuffer()));
}

pub export fn onIngredientResponse() void {
    common.logFailure(PageBuilder.handleIngredientResponse());
}

pub export fn onPropertiesResponse() void {
    common.logFailure(PageBuilder.handlePropertiesResponse());
}

pub export fn onCategoriesResponse() void {
    common.logFailure(PageBuilder.handleCategoriesResponse());
}

pub export fn requestPropertyDelete() void {
    const failable = struct {
        fn f() !void {
            var arena = common.makeArena();
            defer arena.deinit();

            wsr.getSelfAttribute("ingredient-property-id");
            const id = wsr.getInputBuffer();

            const url = try std.fmt.allocPrint(
                arena.allocator(),
                "/ingredient_properties/{s}",
                .{id},
            );

            var req = wsr.RequestFetch.init(url, "DELETE");
            req.addCallback("onPropertyDelete");
            req.run();
        }
    }.f;

    common.logFailure(failable());
}

pub export fn onPropertyDelete() void {
    const failable = struct {
        fn f() !void {
            var arena = common.makeArena();
            defer arena.deinit();

            wsr.getSelfAttribute("delete-id");
            wsr.replaceElemProperty(wsr.getInputBuffer(), "", "outerHTML");
        }
    }.f;

    common.logFailure(failable());
}

pub export fn onPropertyValueChange() void {
    common.logFailure(Page.onPropertyValueChange());
}

pub export fn onPromoteClicked() void {
    common.logFailure(Page.onPromoteClicked());
}

pub export fn onPromoteComplete() void {
    common.logFailure(Page.onPromoteComplete());
}

pub export fn onCompleteChecked() void {
    wsr.getSelfProperty("checked");
    const Bool = enum { true, false };
    const val = std.meta.stringToEnum(Bool, wsr.getInputBuffer()) orelse return;
    common.logFailure(Page.handleComponentChanged("fully_entered", val == .true));
}

pub export fn onAddPropertySelect() void {
    common.logFailure(Page.onAddPropertySelect());
}

pub export fn onPropertyAdded() void {
    common.logFailure(Page.onPropertyAdded());
}

pub export fn onPropertySearchInput() void {
    common.logFailure(Page.onPropertySearchInput());
}
