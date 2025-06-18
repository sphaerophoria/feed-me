const std = @import("std");
const wsr = @import("wsr.zig");

fn numberString(alloc: std.mem.Allocator, num: anytype) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "{d}", .{num});
}

const Page = struct {
    ingredient: Ingredient,
    arena: std.heap.ArenaAllocator,

    var instance: ?Page = null;

    fn initInstance() !*Page {
        if (instance != null) return error.AlreadyInitialized;

        // FIXME: Intermediate data needs to be freed, so more likely parse + clone
        // is better
        // FIXME: free previous ingredient if exists
        const ingredient = try std.json.parseFromSliceLeaky(Ingredient, std.heap.wasm_allocator, wsr.getInputBuffer(), .{ .ignore_unknown_fields = true});

        const arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);

        instance = .{
            .ingredient = ingredient,
            .arena = arena,
        };
        return &instance.?;
    }

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
};

// FIXME: Share with ingredients page
const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: i64,
    serving_size_ml: i64,
    serving_size_pieces: i64,
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
            if (ei.payload == void) {
                return void;
            }

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
            return;
        } else {
            return null;
        }
    };
}

pub export fn makeIngredientContent() void {
    const page = handleError(Page.initInstance()) orelse return;
    handleError(page.makeIngredientContent());
}

pub export fn servingSizeGChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_g"));
}

pub export fn servingSizeMlChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_ml"));
}

pub export fn servingSizePiecesChanged() void {
    const page = handleError(Page.getInstance()) orelse return;
    handleError(page.handleComponentChanged("serving_size_pieces"));
}
