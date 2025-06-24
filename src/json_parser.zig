const std = @import("std");
const wsr = @import("wasm/wsr.zig");

const JsonTokenType = enum {
    object_start,
    object_end,
    array_start,
    array_end,
    colon,
    string,
    number,
    true,
    false,
    null,
    invalid,
};

const JsonLexer = struct {
    content: []const u8,
    idx: usize = 0,

    const Output = struct {
        token_type: JsonTokenType,
        start: usize,
        end: usize,

        fn content(self: Output, buf: []const u8) []const u8 {
            switch (self.token_type) {
                .string => return buf[self.start + 1..self.end - 1],
                else => return buf[self.start..self.end],
            }
        }
    };

    fn init(content: []const u8) JsonLexer {
        return .{
            .content = content,
        };
    }

    fn next(self: *JsonLexer) ?Output {
        self.consumeWhitespace();
        return self.scanValue();
    }

    fn expectToken(self: *JsonLexer, token: JsonTokenType) !Output {
        const res = self.next() orelse return error.NoToken;
        if (res.token_type != token) {
            return error.UnexpectedToken;
        }
        return res;
    }

    fn discardJsonValue(lexer: *JsonLexer) !void {
        const start = lexer.next() orelse return error.NoValue;
        switch (start.token_type) {
            .object_start => try discardObject(lexer),
            .array_start => try discardArray(lexer),
            .colon,
            .string,
            .number,
            .true,
            .false,
            .null => return,
            .array_end,
            .object_end,
            .invalid => return error.InvalidValue,
        }
    }

    fn discardObject(lexer: *JsonLexer) anyerror!void {
        while (true) {
            const key_or_end = lexer.next() orelse return error.UnfinishedObject;
            switch (key_or_end.token_type) {
                .object_end => return,
                .string => {},
                else => return error.UnexpectedToken,
            }
            _ = try lexer.expectToken(.colon);
            try discardJsonValue(lexer);
        }
    }

    fn discardArray(lexer: *JsonLexer) !void {
        while (true) {
            const start = lexer.next() orelse return error.NoValue;
            switch (start.token_type) {
                .object_start => try discardObject(lexer),
                .array_start => try discardArray(lexer),
                .array_end => return,
                .string,
                .number,
                .true,
                .false,
                .null => continue,
                .object_end,
                .colon,
                .invalid => return error.InvalidValue,
            }
        }
    }

    fn nextAsInt(self: *JsonLexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseInt(T, res.content(self.content), 0);
    }

    fn nextAsFloat(self: *JsonLexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseFloat(T, res.content(self.content));
    }

    fn consumeWhitespace(self: *JsonLexer) void {
        const ws_chars = [_]u8{0x20, 0x0A, 0x0D, 0x09, ','};
        self.idx = std.mem.indexOfNonePos(u8, self.content, self.idx, &ws_chars) orelse self.content.len;
    }

    const ScanResult = struct {
        const invalid: ScanResult = .{ .token = .invalid, .consumed_bytes = 0 };

        token: JsonTokenType,
        consumed_bytes: usize,
    };

    fn scanValue(self: *JsonLexer) ?Output {
        if (self.idx >= self.content.len) return null;
        const scan_res: ScanResult = switch (self.content[self.idx]) {
            '{' => .{.token = JsonTokenType.object_start, .consumed_bytes= 1},
            '}' => .{.token = JsonTokenType.object_end, .consumed_bytes= 1},
            '[' => .{.token = JsonTokenType.array_start, .consumed_bytes= 1},
            ']' => .{.token = JsonTokenType.array_end, .consumed_bytes= 1},
            ':' => .{.token = JsonTokenType.colon, .consumed_bytes = 1},
            '"' => self.scanStringEnd(),
            't' => self.scanTrue(),
            'f' => self.scanFalse(),
            'n' => self.scanNull(),
            '0'...'9' => self.scanNumber(),
            else => .{.token = JsonTokenType.invalid, .consumed_bytes= 0},
        };

        defer self.idx += scan_res.consumed_bytes;

        return .{
            .token_type = scan_res.token,
            .start = self.idx,
            .end = self.idx + scan_res.consumed_bytes,
        };
    }

    fn scanStringEnd(self: *JsonLexer) ScanResult {
        var idx = self.idx + 1;
        while (true) {
            const potential_match = std.mem.indexOfScalarPos(u8, self.content, idx, '"') orelse return .invalid;
            var bs_pos = potential_match - 1;
            var bs_count: usize = 0;

            // NOTE: Always have parsed at least 1 quote before now, so we can
            // go backwards forever without bounds checking because eventually
            // it won't be a \
            while (self.content[bs_pos] == '\\') {
                bs_count += 1;
                bs_pos -= 1;
            }

            if (bs_count % 2 == 0) {
                return .{
                    .token = .string,
                    .consumed_bytes = potential_match - self.idx + 1,
                };
            }

            idx = potential_match + 1;
        }
    }

    fn scanIdentifier(self: *JsonLexer, ident: []const u8, on_match: JsonTokenType) ScanResult {
        if (self.idx + ident.len > self.content.len) {
            return .invalid;
        }

        if (std.mem.eql(u8, self.content[self.idx..self.idx + ident.len], ident)) {
            return .{
                .token = on_match,
                .consumed_bytes = ident.len,
            };
        }

        return .invalid;
    }

    fn scanTrue(self: *JsonLexer) ScanResult {
        return self.scanIdentifier("true", .true);
    }

    fn scanFalse(self: *JsonLexer) ScanResult {
        return self.scanIdentifier("false", .false);
    }

    fn scanNull(self: *JsonLexer) ScanResult {
        return self.scanIdentifier("null", .null);
    }

    fn scanNumber(self: *JsonLexer) ScanResult {
        var idx = self.idx + 1;
        while (idx < self.content.len) {
            const val = self.content[idx];
            if (val != '.' and val < '0' or val > '9') {
                return .{
                    .token = .number,
                    .consumed_bytes = idx - self.idx,
                };
            }

            idx += 1;
        }

        return .{
            .token = .number,
            .consumed_bytes = idx - self.idx,
        };
    }
};

const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    value: f32,

    fn parseJson(lexer: *JsonLexer) !IngredientProperty {
        const initial_lexer = lexer.*;
        errdefer {
            lexer.* = initial_lexer;
        }

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var ingredient_id: ?i64 = null;
        var property_id: ?i64 = null;
        var out_value: ?f32 = null;

        while (true) {
            const key_or_end = lexer.next() orelse return error.UnfinishedObject;
            switch (key_or_end.token_type)  {
                .object_end => break,
                .string => {},
                else => return error.InvalidKey,
            }
            _ = try lexer.expectToken(.colon);

            const key_content = key_or_end.content(lexer.content);
            if (std.mem.eql(u8, "id", key_content)) {
                id = try lexer.nextAsInt(i64);
            } else if (std.mem.eql(u8, "ingredient_id", key_content)) {
                ingredient_id = try lexer.nextAsInt(i64);
            } else if (std.mem.eql(u8, "property_id", key_content)) {
                property_id = try lexer.nextAsInt(i64);
            } else if (std.mem.eql(u8, "value", key_content)) {
                out_value = try lexer.nextAsFloat(f32);
            } else {
                try lexer.discardJsonValue();
            }
        }

        return .{
            .id = id orelse return error.MissingId,
            .ingredient_id = ingredient_id orelse return error.MissingIngredientId,
            .property_id = property_id orelse return error.MissingPropertyId,
            .value = out_value orelse return error.MissingValue,
        };

    }
};

const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: f32,
    serving_size_ml: f32,
    serving_size_pieces: f32,
    properties: []IngredientProperty,

    fn parseJson(alloc: std.mem.Allocator, blob: []const u8) !Ingredient {
        var lexer = JsonLexer.init(blob);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var serving_size_g: ?f32 = null;
        var serving_size_ml: ?f32 = null;
        var serving_size_pieces: ?f32 = null;
        var properties: std.ArrayListUnmanaged(IngredientProperty) = .{};

        while (true) {
            const key_or_end = lexer.next() orelse return error.UnfinishedObject;
            switch (key_or_end.token_type)  {
                .object_end => break,
                .string => {},
                else => return error.InvalidKey,
            }
            _ = try lexer.expectToken(.colon);

            const key_content = key_or_end.content(blob);
            if (std.mem.eql(u8, "id", key_content)) {
                const value = try lexer.expectToken(.number);
                id = try std.fmt.parseInt(i64, value.content(blob), 0);
            } else if (std.mem.eql(u8, "name", key_content)) {
                const value = try lexer.expectToken(.string);
                name = value.content(blob);
            } else if (std.mem.eql(u8, "serving_size_g", key_content)) {
                const value = try lexer.expectToken(.number);
                serving_size_g = try std.fmt.parseFloat(f32, value.content(blob));
            } else if (std.mem.eql(u8, "serving_size_ml", key_content)) {
                const value = try lexer.expectToken(.number);
                serving_size_ml = try std.fmt.parseFloat(f32, value.content(blob));
            } else if (std.mem.eql(u8, "serving_size_pieces", key_content)) {
                const value = try lexer.expectToken(.number);
                serving_size_pieces = try std.fmt.parseFloat(f32, value.content(blob));
            } else if (std.mem.eql(u8, "properties", key_content)) {
                _ = try lexer.expectToken(.array_start);
                while (true) {
                    const property = IngredientProperty.parseJson(&lexer) catch {
                        _ = try lexer.expectToken(.array_end);
                        break;
                    };
                    try properties.append(alloc, property);
                }
            } else {
                try lexer.discardJsonValue();
            }
        }

        return .{
            .id = id orelse return error.MissingId,
            .name = name orelse return error.MissingName,
            .serving_size_g = serving_size_g orelse return error.MissingServingG,
            .serving_size_ml = serving_size_ml orelse return error.MissingServingMl,
            .serving_size_pieces = serving_size_pieces orelse return error.MissingServingPieces,
            .properties = properties.items,
        };
    }
};

pub export fn parse() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    const value = Ingredient.parseJson(arena.allocator(), wsr.getInputBuffer());
    wsr.print("{any}", .{value});
}

//pub fn main() !void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
//    defer _ = gpa.deinit();
//
//    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
//    defer arena.deinit();
//
//    const f = try std.fs.cwd().openFile("test.json", .{});
//    const content = try f.readToEndAlloc(arena.allocator(), 1 << 20);
//    std.debug.print("{s}\n", .{content});
//
//    var lexer = JsonLexer { .content = content };
//    while (lexer.next()) |token| {
//        std.debug.print("{s}: {s}\n", .{@tagName(token.token_type), content[token.start..token.end]});
//        if (token.token_type == .invalid) {
//            std.debug.print("{c}\n", .{content[lexer.idx]});
//        }
//        std.debug.assert(token.token_type != .invalid);
//    }
//
//    const ingredient = try Ingredient.parseJson(arena.allocator(), content);
//    std.debug.print("{any}\n", .{ingredient});
//}
