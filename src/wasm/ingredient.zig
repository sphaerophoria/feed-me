const std = @import("std");
const wsr = @import("wsr.zig");
const htmlgen = @import("htmlgen.zig");

fn numberString(alloc: std.mem.Allocator, num: anytype) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d}", .{num});
}

const PageBuilder = struct {
    ingredient: ?Ingredient = null,
    properties: ?[]Property = null,

    var instance: ?PageBuilder = null;

    fn initInstance() !*PageBuilder {
        if (instance != null) return error.AlreadyInitialized;
        instance = .{};
        return &instance.?;
    }

    fn getInstance() !*PageBuilder {
        if (instance == null) return error.NotInitialized;
        return &instance.?;
    }

    fn handlePropertiesResponse(self: *PageBuilder) !void {
        if (self.properties != null) return error.AlreadyInitialized;
        self.properties = try std.json.parseFromSliceLeaky([]Property, std.heap.wasm_allocator, wsr.getInputBuffer(), .{ .ignore_unknown_fields = true, .allocate = .alloc_always});

    }

    fn handleIngredientResponse(self: *PageBuilder) !void {
        if (self.ingredient != null) return error.AlreadyInitialized;
        self.ingredient = try std.json.parseFromSliceLeaky(Ingredient, std.heap.wasm_allocator, wsr.getInputBuffer(), .{ .ignore_unknown_fields = true, .allocate = .alloc_always});
        wsr.print("{any}", .{self.ingredient.?.name.ptr});
    }

    fn buildIfReady(self: *PageBuilder) !void {
        const ingredient = self.ingredient orelse return;
        wsr.print("later {d}\n", .{ingredient.name.len});
        wsr.print("{any}", .{ingredient.name.ptr});
        wsr.print("{any}", .{ingredient.name});
        const properties = self.properties orelse return;
        Page.instance = .{
            .ingredient = ingredient,
            .properties = properties,
            .arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator),
        };
        try Page.instance.?.makeIngredientContent();
    }
};

const Page = struct {
    ingredient: Ingredient,
    properties: []Property,
    arena: std.heap.ArenaAllocator,

    var instance: ?Page = null;

    fn getInstance() !*Page {
        if (instance == null) {
            return error.Uninitialized;
        }
        return &instance.?;
    }

    fn makeIngredientContent(self: *Page) !void {
        defer _ = self.arena.reset(.retain_capacity);

        wsr.replaceElemContent("title", self.ingredient.name, "value");

        const serving_size_g_text = try numberString(self.arena.allocator(), self.ingredient.serving_size_g);
        wsr.replaceElemContent("serving_size_g", serving_size_g_text, "value");

        const serving_size_ml_text = try numberString(self.arena.allocator(), self.ingredient.serving_size_ml);
        wsr.replaceElemContent("serving_size_ml", serving_size_ml_text, "value");

        const serving_size_pieces_text = try numberString(self.arena.allocator(), self.ingredient.serving_size_pieces);
        wsr.replaceElemContent("serving_size_pieces", serving_size_pieces_text, "value");

        var property_buf = std.ArrayList(u8).init(self.arena.allocator());
        try property_buf.ensureTotalCapacity(4096);

        var html_writer = htmlgen.htmlWriter(property_buf.writer());
        for (self.ingredient.properties) |ingredient_property| {
            const property = self.propertyById(ingredient_property.property_id) orelse {
                wsr.print("ERROR: Missing property id: {d}", .{ingredient_property.property_id});
                continue;
            };

            const ingredient_property_id_string = try numberString(self.arena.allocator(), ingredient_property.id);
            try html_writer.openTag("sphdelete-button");
            try html_writer.attribute("wsr-onevent", "click");
            try html_writer.attribute("wsr-generate", "requestPropertyDelete");
            try html_writer.attribute("wsr-argument-direct", ingredient_property_id_string);
            try html_writer.attribute("ingredient-property-id", ingredient_property_id_string);
            try html_writer.closeTag("sphdelete-button");

            try html_writer.openTag("label");
            try html_writer.attribute("ingredient-property-id", ingredient_property_id_string);
            try html_writer.content(property.name);
            try html_writer.closeTag("label");

            try html_writer.openTag("input");
            try html_writer.attribute("ingredient-property-id", ingredient_property_id_string);
            try html_writer.attribute("wsr-onevent", "change");
            try html_writer.attribute("wsr-argument-property", "value");
            try html_writer.attribute("wsr-generate", "onPropertyValueChange");
            try html_writer.attribute("type", "number");

            const value_string = try numberString(self.arena.allocator(), ingredient_property.value);
            try html_writer.attribute("value", value_string);
            try html_writer.selfClose();
        }

        wsr.replaceElemContent("ingredient_properties", property_buf.items, "innerHTML");
    }

    fn servingSizeGChanged(self: *Page) !void {
        defer _ = self.arena.reset(.retain_capacity);

        const new_size = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
        const body = try std.json.stringifyAlloc(self.arena.allocator(), IngredientModificationReq {
            .serving_size_g = new_size,
        }, .{});

        const put_url = try std.fmt.allocPrint(self.arena.allocator(), "/ingredients/{d}", .{self.ingredient.id});
        wsr.requestPut(put_url, body);
    }

    fn handleComponentChanged(self: *Page, comptime name: []const u8) !void {
        defer _ = self.arena.reset(.retain_capacity);

        const new_value = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
        var req = IngredientModificationReq{};
        @field(req, name) = new_value;
        const body = try std.json.stringifyAlloc(self.arena.allocator(), req, .{.emit_null_optional_fields = false});

        const put_url = try std.fmt.allocPrint(self.arena.allocator(), "/ingredients/{d}", .{self.ingredient.id});
        wsr.requestPut(put_url, body);
    }

    fn propertyById(self: Page, id: i64) ?Property {
        // FIXME: HashMap
        for (self.properties) |prop| {
            if (prop.id == id) return prop;
        }
        return null;
    }

    fn onPropertyValueChange(self: *Page) !void {
        defer _ = self.arena.reset(.retain_capacity);
        // FIXME: Do we still need all these argument types?
        wsr.getSelfAttribute("ingredient-property-id");
        const id_s = try self.arena.allocator().dupe(u8, wsr.getInputBuffer());

        wsr.getSelfProperty("value");
        const value_s = try self.arena.allocator().dupe(u8, wsr.getInputBuffer());

        const url = try std.fmt.allocPrint(self.arena.allocator(), "/ingredient_properties/{s}", .{id_s});
        const body = try std.json.stringifyAlloc(self.arena.allocator(),
            IngredientPropertyMod {
                .value = value_s,
            },
            .{},
        );
        wsr.requestFetch(
            url,
            body,
            "PUT",
            &.{},
            &.{},
        );
    }
};

// FIXME: Share with ingredients page
const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: i64,
    serving_size_ml: i64,
    serving_size_pieces: i64,
    properties: []IngredientProperty,
};

const Property = struct {
    id: i64,
    name: []const u8,
};

const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    // FIXME: FixedPointNum
    value: f32,
};

const IngredientPropertyMod = struct {
    // FIXME: FixedPointNum
    value: []const u8,
};

const IngredientModificationReq = struct {
    serving_size_g: ?i64 = null,
    serving_size_ml: ?i64 = null,
    serving_size_pieces: ?i64 = null,
};


fn ErrorAsOptional(comptime T: anytype) type {
    const ti = @typeInfo(T);
    switch (ti) {
        .error_union => |ei| {
            return @Type(.{
                .optional = .{
                    .child = ei.payload,
                },
            });
        },
        else => @compileError("Not an error type"),
    }
}

fn handleError(value: anytype) ErrorAsOptional(@TypeOf(value)) {
    const RetT = ErrorAsOptional(@TypeOf(value));
    return value catch |e| {
        wsr.print("{s}", .{@errorName(e)});
        if (RetT == void) {
            return null;
        } else {
            return null;
        }
    };
}

pub export fn servingSizeGChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_g")) orelse return;
}

pub export fn servingSizeMlChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_ml")) orelse return;
}

pub export fn servingSizePiecesChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_pieces")) orelse return;
}

fn tryPageInit() !void {
    _ = try PageBuilder.initInstance();

    const id = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
    var url_buf: [50]u8 = undefined;
    const url = try std.fmt.bufPrint(&url_buf, "/ingredients/{d}", .{id});
    wsr.requestFetch(
        url,
        &.{},
        "GET",
        "onIngredientResponse",
        &.{},
    );

    wsr.requestFetch(
        "/properties",
        &.{},
        "GET",
        "onPropertiesResponse",
        &.{},
    );
}

pub export fn pageInit() void {
    handleError(tryPageInit()) orelse return;
}

pub export fn onIngredientResponse() void {
    const page_builder = handleError(PageBuilder.getInstance()) orelse return;
    handleError(page_builder.handleIngredientResponse()) orelse return;
    handleError(page_builder.buildIfReady()) orelse return;
}

pub export fn onPropertiesResponse() void {
    const page_builder = handleError(PageBuilder.getInstance()) orelse return;
    handleError(page_builder.handlePropertiesResponse()) orelse return;
    handleError(page_builder.buildIfReady()) orelse return;
}

pub export fn requestPropertyDelete() void {
    const id = wsr.getInputBuffer();
    var url_buf: [100]u8 = undefined;
    const url = handleError(std.fmt.bufPrint(&url_buf, "/ingredient_properties/{s}", .{id})) orelse return;
    wsr.requestFetch(
        url,
        &.{},
        "DELETE",
        "onPropertyDelete",
        id,
    );
}
pub export fn onPropertyDelete() void {
    wsr.print("Deleted {s}!", .{wsr.getInputBuffer()});
    var query_buf: [100]u8 = undefined;
    const query = handleError(std.fmt.bufPrint(&query_buf, "[ingredient-property-id=\"{s}\"]", .{wsr.getInputBuffer()})) orelse return;
    wsr.deleteElemByQuery(query);
}

pub export fn onPropertyValueChange() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.onPropertyValueChange()) orelse return;
}
