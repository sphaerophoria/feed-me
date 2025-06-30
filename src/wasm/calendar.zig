const std = @import("std");
const common = @import("common.zig");
const wsr = @import("wsr.zig");
const json = @import("json.zig");
const htmlgen = @import("htmlgen.zig");

const Meal = struct {
    id: i64,
    timestamp_utc: i64,

    fn parse(lexer: *json.Lexer) !Meal {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var timestamp_utc: ?i64 = null;

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(std.meta.FieldEnum(Meal), key_s) orelse {
                try lexer.discardValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsInt(i64),
                .timestamp_utc => timestamp_utc = try lexer.nextAsInt(i64),
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .timestamp_utc = timestamp_utc orelse return error.MissingField,
        };
    }
};

var meals: ?[]const Meal = null;

extern fn triggerCalendarUpdate() void;

const MealParseCtx = struct {
    pub fn parse(_: @This(), lexer: *json.Lexer) !Meal {
        return Meal.parse(lexer);
    }
};

pub fn onMealFailable() !void {
    var lexer = json.Lexer.init(wsr.getInputBuffer());

    meals = try lexer.parseList(Meal, MealParseCtx{}, std.heap.wasm_allocator);

    triggerCalendarUpdate();
}

pub export fn onMeals() void {
    common.logFailure(onMealFailable());
}

pub fn onCalendarUpdateFailable() !void {
    wsr.getSelfAttribute("timestamp-start");
    const start = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);

    wsr.getSelfAttribute("timestamp-end");
    const end = try std.fmt.parseInt(i64, wsr.getInputBuffer(), 0);

    var arena = common.makeArena();
    defer arena.deinit();

    var out_buf = std.ArrayList(u8).init(arena.allocator());
    var writer = htmlgen.htmlWriter(out_buf.writer());

    for (meals.?) |meal| {
        // FIXME: More intelligent meal lookup
        if (meal.timestamp_utc >= start and meal.timestamp_utc < end) {
            const url = try std.fmt.allocPrint(arena.allocator(), "/meal.html?id={d}", .{meal.id});
            const meal_link_content = try std.fmt.allocPrint(arena.allocator(), "Meal {d}", .{meal.id});

            try writer.openTag("a");
            try writer.attribute("href", url);
            try writer.content(meal_link_content);
            try writer.closeTag("a");

            try writer.openTag("br");
            try writer.selfClose();
        }
    }

    wsr.replaceSelfProperty(out_buf.items, "innerHTML");
}

pub export fn onCalendarUpdate() void {
    common.logFailure(onCalendarUpdateFailable());
}
