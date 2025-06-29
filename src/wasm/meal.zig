const wsr = @import("wsr.zig");
const common = @import("common.zig");
const data = @import("data.zig");

pub export fn onMeal() void {
    wsr.writeStdout(wsr.getInputBuffer());
}

pub export fn onIngredients() void {
    wsr.writeStdout(wsr.getInputBuffer());
}

pub fn onPropertiesFailable() !void {
    var arena = common.makeArena();
    defer arena.deinit();

    var properties = try data.Properties.parse(arena.allocator(), wsr.getInputBuffer());
    var it = properties.iter(arena.allocator());

    var indent: usize = 0;
    while (try it.next()) |elem| {
        const name = switch (elem) {
            .indent_up => |e| blk: {
                indent += 1;
                break :blk e.name;
            },
            .level => |e| e.name,
            .indent_down => {
                indent -= 1;
                continue;
            },
        };
        wsr.print("{d}: {s}", .{ indent, name });
    }
}
pub export fn onProperties() void {
    common.logFailure(onPropertiesFailable());
}

pub export fn onDishes() void {
    wsr.writeStdout(wsr.getInputBuffer());
}
