const std = @import("std");
const common = @import("common.zig");
const json = @import("json.zig");
const wsr = @import("wsr.zig");
const htmlgen = @import("htmlgen.zig");
const data = @import("data.zig");

const Property = data.Property;
const Properties = data.Properties;
const PropertyMap = data.Properties.PropertyMap;
const ChildMap = data.Properties.ChildMap;

pub const returnErrorHook = wsr.returnErrorHook;

fn makePropertyInput(property: Properties.Iter.PropertyElem, out: anytype) !void {
    var id_s_buf: [10]u8 = undefined;
    const id_s = try std.fmt.bufPrint(&id_s_buf, "{d}", .{property.id});

    try out.openTag("input");
    try out.attribute("value", property.name);
    try out.attribute("type", "text");
    try out.attribute("property-id", id_s);
    try out.attribute("wsr-onevent", "input");
    try out.attribute("wsr-generate", "onNameChange");
    try out.selfClose();

}

fn writePropertiesHtml(alloc: std.mem.Allocator, properties: *const Properties) !void {
    var out_buf = std.ArrayList(u8).init(alloc);
    var writer = htmlgen.htmlWriter(out_buf.writer());

    var it = properties.iter(alloc);
    while (try it.next()) |entry| {
        switch (entry) {
            .indent_up => |p| {
                try writer.openTag("div");
                try writer.attribute("class", "input_2");
                try makePropertyInput(p, &writer);
            },
            .level => |p| {
                try makePropertyInput(p, &writer);
            },
            .indent_down => {

                try writer.closeTag("div");
            },
        }
    }

    wsr.replaceSelfProperty(out_buf.items, "innerHTML");
}

fn onPropertiesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const properties = try Properties.parse(arena.allocator(), wsr.getInputBuffer());

    try writePropertiesHtml(arena.allocator(), &properties);
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
