const std = @import("std");
const wsr = @import("wsr.zig");
const htmlgen = @import("htmlgen.zig");

fn numberString(alloc: std.mem.Allocator, num: anytype) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d}", .{num});
}

fn makeArena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
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

    fn handlePropertiesResponse() !void {
        const self = try getInstance();
        if (self.properties != null) return error.AlreadyInitialized;
        self.properties = try std.json.parseFromSliceLeaky(
            []Property,
            std.heap.wasm_allocator,
            wsr.getInputBuffer(),
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        try self.buildIfReady();
    }

    fn handleIngredientResponse() !void {
        const self = try getInstance();
        if (self.ingredient != null) return error.AlreadyInitialized;
        self.ingredient = try std.json.parseFromSliceLeaky(
            Ingredient,
            std.heap.wasm_allocator,
            wsr.getInputBuffer(),
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        try self.buildIfReady();
    }

    fn buildIfReady(self: *PageBuilder) !void {
        const ingredient = self.ingredient orelse return;
        const properties = self.properties orelse return;
        Page.instance = .{
            .ingredient = ingredient,
            .properties = properties,
        };
        try Page.instance.?.makeIngredientContent();
    }
};

const Page = struct {
    ingredient: Ingredient,
    properties: []Property,

    var instance: ?Page = null;

    fn getInstance() !*Page {
        if (instance == null) {
            return error.Uninitialized;
        }
        return &instance.?;
    }

    fn makeIngredientContent(self: *Page) !void {
        var arena = makeArena();
        defer arena.deinit();

        wsr.replaceElemProperty("title", self.ingredient.name, "value");

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
            const property = self.propertyById(ingredient_property.property_id) orelse {
                wsr.print("ERROR: Missing property id: {d}", .{ingredient_property.property_id});
                continue;
            };

            const ingredient_property_id_string = try numberString(arena.allocator(), ingredient_property.id);

            const id_prop = try std.fmt.allocPrint(
                arena.allocator(),
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
            try html_writer.attribute("wsr-onevent", "change");
            try html_writer.attribute("wsr-generate", "onPropertyValueChange");
            try html_writer.attribute("type", "number");

            const value_string = try numberString(arena.allocator(), ingredient_property.value);
            try html_writer.attribute("value", value_string);
            try html_writer.selfClose();
            try html_writer.closeTag("div");
        }

        wsr.replaceElemProperty("ingredient_properties", property_buf.items, "innerHTML");
    }

    fn servingSizeGChanged(self: *Page) !void {
        var arena = makeArena();
        defer arena.deinit();

        const new_size = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
        const body = try std.json.stringifyAlloc(arena.allocator(), IngredientModificationReq{
            .serving_size_g = new_size,
        }, .{});

        const put_url = try std.fmt.allocPrint(arena.allocator(), "/ingredients/{d}", .{self.ingredient.id});
        wsr.requestPut(put_url, body);
    }

    fn handleComponentChanged(comptime name: []const u8) !void {
        const self = try getInstance();
        var arena = makeArena();
        defer arena.deinit();

        const new_value = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);

        var req = IngredientModificationReq{};
        @field(req, name) = new_value;

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
        var arena = makeArena();
        defer arena.deinit();

        // FIXME: Do we still need all these argument types?
        wsr.getSelfAttribute("ingredient-property-id");
        const id_s = try arena.allocator().dupe(u8, wsr.getInputBuffer());

        wsr.getSelfProperty("value");
        const value_s = try arena.allocator().dupe(u8, wsr.getInputBuffer());

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

fn logFailure(value: anytype) void {
    value catch |e| {
        wsr.print("{s}", .{@errorName(e)});
    };
}

pub export fn servingSizeGChanged() void {
    logFailure(Page.handleComponentChanged("serving_size_g"));
}

pub export fn servingSizeMlChanged() void {
    logFailure(Page.handleComponentChanged("serving_size_ml"));
}

pub export fn servingSizePiecesChanged() void {
    logFailure(Page.handleComponentChanged("serving_size_pieces"));
}

pub export fn pageInit() void {
    const failable = struct {
        fn f() !void {
            var arena = makeArena();
            defer arena.deinit();

            _ = try PageBuilder.initInstance();

            wsr.getSelfProperty("ingredient_id");
            const id = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);
            const url = try std.fmt.allocPrint(
                arena.allocator(),
                "/ingredients/{d}",
                .{id},
            );

            var req = wsr.RequestFetch.init(url, "GET");
            req.addCallback("onIngredientResponse");
            req.run();

            req = wsr.RequestFetch.init("/properties", "GET");
            req.addCallback("onPropertiesResponse");
            req.run();
        }
    }.f;

    logFailure(failable());
}

pub export fn onIngredientResponse() void {
    logFailure(PageBuilder.handleIngredientResponse());
}

pub export fn onPropertiesResponse() void {
    logFailure(PageBuilder.handlePropertiesResponse());
}

pub export fn requestPropertyDelete() void {
    const failable = struct {
        fn f() !void {
            var arena = makeArena();
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

    logFailure(failable());
}

pub export fn onPropertyDelete() void {
    const failable = struct {
        fn f() !void {
            var arena = makeArena();
            defer arena.deinit();

            wsr.getSelfAttribute("delete-id");
            wsr.replaceElemProperty(wsr.getInputBuffer(), "", "outerHTML");
        }
    }.f;

    logFailure(failable());
}

pub export fn onPropertyValueChange() void {
    logFailure(Page.onPropertyValueChange());
}
