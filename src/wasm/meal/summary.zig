const data = @import("data.zig");
const common_data = @import("../data.zig");
const common = @import("../common.zig");
const std = @import("std");
const htmlgen = @import("../htmlgen.zig");
const wsr = @import("../wsr.zig");

extern fn markSummaryComplete(id_ptr: [*]const u8, id_len: usize) void;

pub fn makeSummary(properties: *const common_data.Properties, meal: *const data.Meal) !void {
    var arena = common.makeArena();
    defer arena.deinit();

    const alloc = arena.allocator();

    var property_it = properties.iter(alloc);

    var html_buf = std.ArrayList(u8).init(alloc);
    var writer = htmlgen.htmlWriter(html_buf.writer());

    var margin: i32 = 0;

    while (try property_it.next()) |entry| {
        switch (entry) {
            .level => |prop| {
                try writePropSummary(prop, meal, margin, &writer);
            },
            .indent_up => |prop| {
                margin += 2;
                try writePropSummary(prop, meal, margin, &writer);
            },
            .indent_down => {
                margin -= 2;
            },
        }
    }

    wsr.replaceElemProperty("summary", html_buf.items, "innerHTML");

    if (meal.summary_complete) {
        const summary_key = "summary";
        markSummaryComplete(summary_key.ptr, summary_key.len);
    }
}

fn writePropSummary(prop: common_data.Properties.Iter.PropertyElem, meal: *const data.Meal, margin: i32, writer: anytype) !void {
    const value = meal.summary.get(prop.id) orelse return;

    var key_style_buf: [20]u8 = undefined;
    const key_style_string = try std.fmt.bufPrint(&key_style_buf, "margin-left: {d}em", .{margin});
    try writer.openTag("div");
    try writer.attribute("style", key_style_string);
    try writer.content(prop.name);
    try writer.closeTag("div");

    try writer.openTag("div");
    try writer.attribute("style", "justify-self: end; text-align: end");
    try writer.content(value);
    try writer.closeTag("div");
}
