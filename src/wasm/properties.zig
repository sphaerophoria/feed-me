const std = @import("std");
const common = @import("common.zig");
const json = @import("json.zig");
const wsr = @import("wsr.zig");
const htmlgen = @import("htmlgen.zig");

pub const returnErrorHook = wsr.returnErrorHook;

const Property = struct {
    name: []const u8,
    parent_id: ?i64,
};

const ChildMap = std.AutoHashMap(i64, std.ArrayList(i64));
const PropertyMap = std.AutoArrayHashMap(i64, Property);

fn parseProperty(alloc: std.mem.Allocator, lexer: *json.Lexer, out: *PropertyMap) !void {
    const cp = lexer.checkpoint();
    errdefer lexer.restore(cp);

    _ = try lexer.expectToken(.object_start);

    var id: ?i64 = null;
    var name: ?[]const u8 = null;
    var parent_id: ?i64 = null;

    const Fields = enum {id, name, parent_id};

    while (try lexer.objectKeyOrEnd()) |key_s| {
        const key = std.meta.stringToEnum(Fields, key_s) orelse {
            try lexer.discardValue();
            continue;
        };

        switch (key) {
            .id => id = try lexer.nextAsInt(i64),
            .name => name = try lexer.nextAsStringRef(alloc),
            .parent_id => parent_id = try lexer.nextAsInt(i64),
        }
    }

    try out.put(id orelse return error.MissingField, .{
        .name = name orelse return error.MissingField,
        .parent_id = parent_id,
    });
}

fn parseProperties(alloc: std.mem.Allocator) !std.AutoArrayHashMap(i64, Property) {
    var lexer = json.Lexer.init(wsr.getInputBuffer());

    _ = try lexer.expectToken(.array_start);
    var ret = std.AutoArrayHashMap(i64, Property).init(alloc);
    while (true) {
        parseProperty(alloc, &lexer, &ret) catch |e| {
            _ = lexer.expectToken(.array_end) catch return e;
            break;
        };
    }

    return ret;
}

fn buildChildMap(alloc: std.mem.Allocator, properties: *const PropertyMap) !ChildMap {
    var it = properties.iterator();
    var child_map = std.AutoHashMap(i64, std.ArrayList(i64)).init(alloc);
    while (it.next()) |entry| {
        const parent = entry.value_ptr.parent_id orelse continue;
        const gop = try child_map.getOrPut(parent);
        if (!gop.found_existing) {
            gop.value_ptr.* = .init(alloc);
        }
        try gop.value_ptr.append(entry.key_ptr.*);
    }
    return child_map;
}

fn writePropertyHtml(alloc: std.mem.Allocator, id: i64, property: Property, properties: *const PropertyMap, child_map: *const ChildMap, out: anytype) !void {
    var id_s_buf: [10]u8 = undefined;
    const id_s = try std.fmt.bufPrint(&id_s_buf, "{d}", .{id});

    try out.openTag("input");
    try out.attribute("value", property.name);
    try out.attribute("type", "text");
    try out.attribute("property-id", id_s);
    try out.attribute("wsr-onevent", "input");
    try out.attribute("wsr-generate", "onNameChange");
    try out.selfClose();

    const child_list = child_map.get(id) orelse return;
    try out.openTag("div");
    try out.attribute("class", "input_2");
    for (child_list.items) |child_id| {
        const child_property = properties.get(child_id) orelse return error.MissingProperty;
        try writePropertyHtml(alloc, child_id, child_property, properties, child_map, out);
    }
    try out.closeTag("div");
}

fn writePropertiesHtml(alloc: std.mem.Allocator, properties: *const std.AutoArrayHashMap(i64, Property), child_map: *const ChildMap,) !void {
    var out_buf = std.ArrayList(u8).init(alloc);
    var writer = htmlgen.htmlWriter(out_buf.writer());

    var it = properties.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.parent_id != null) continue;

        try writePropertyHtml(alloc, entry.key_ptr.*, entry.value_ptr.*, properties, child_map, &writer);
    }

    wsr.replaceSelfProperty(out_buf.items, "innerHTML");
}

fn onPropertiesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const properties = try parseProperties(arena.allocator());
    const child_map = try buildChildMap(arena.allocator(), &properties);

    try writePropertiesHtml(arena.allocator(), &properties, &child_map);
}

pub export fn onProperties() void {
    common.logFailure(onPropertiesFailable());
}

pub fn onNameChangeFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    wsr.getSelfAttribute("property-id");
    const url = try std.fmt.allocPrint(arena.allocator(), "/properties/{s}", .{wsr.getInputBuffer()});

    wsr.getSelfProperty("value");
    const name = wsr.getInputBuffer();
    const body = try std.json.stringifyAlloc(
        arena.allocator(),
        .{
            .name = name,
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
