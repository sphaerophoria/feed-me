const std = @import("std");
const wsr = @import("wasm/wsr.zig");

pub const panic = wsr.panic;

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

    pub fn init(content: []const u8) JsonLexer {
        return .{
            .content = content,
        };
    }

    pub fn next(self: *JsonLexer) ?Output {
        self.consumeWhitespace();
        return self.scanValue();
    }

    pub fn expectToken(self: *JsonLexer, token: JsonTokenType) !Output {
        const res = self.next() orelse return error.NoToken;
        if (res.token_type != token) {
            return error.UnexpectedToken;
        }
        return res;
    }

    pub fn objectKeyOrEnd(self: *JsonLexer) !?[]const u8 {
        const key_or_end = self.next() orelse return error.NoToken;
        switch (key_or_end.token_type) {
            .object_end => return null,
            .string => {},
            else => return error.InvalidKey,
        }
        _ = try self.expectToken(.colon);
        return key_or_end.content(self.content);
    }

    pub fn discardJsonValue(lexer: *JsonLexer) !void {
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

    pub fn discardObject(lexer: *JsonLexer) anyerror!void {
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

    pub fn discardArray(lexer: *JsonLexer) !void {
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

    pub fn nextAsString(self: *JsonLexer) ![]const u8 {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .string => {},
            .number => {},
            else => return error.InvalidType,
        }

        return res.content(self.content);
    }

    pub fn nextAsInt(self: *JsonLexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseInt(T, res.content(self.content), 0);
    }

    pub fn nextAsFloat(self: *JsonLexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseFloat(T, res.content(self.content));
    }

    pub fn checkpoint(self: JsonLexer) usize {
        return self.idx;
    }

    pub fn restore(self: *JsonLexer, restore_point: usize) void  {
        self.idx = restore_point;
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

    fn scanIdentifier(self: *JsonLexer, comptime ident: []const u8, comptime on_match: JsonTokenType) ScanResult {
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
    id: []const u8,
    ingredient_id: []const u8,
    property_id: []const u8,
    value: []const u8,

    fn parseJson(lexer: *JsonLexer) !IngredientProperty {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);

        var ret: IngredientProperty = undefined;

        const Field = std.meta.FieldEnum(IngredientProperty);

        while (try lexer.objectKeyOrEnd()) |key_s|{
            const field = std.meta.stringToEnum(Field, key_s) orelse {
                try lexer.discardJsonValue();
                continue;
            };

            switch (field) {
                .id => ret.id = try lexer.nextAsString(),
                .ingredient_id => ret.ingredient_id = try lexer.nextAsString(),
                .property_id => ret.property_id = try lexer.nextAsString(),
                .value => ret.value = try lexer.nextAsString(),
            }
        }

        return ret;
    }
};

const Ingredient = struct {
    id: []const u8,
    name: []const u8,
    serving_size_g: []const u8,
    serving_size_ml: []const u8,
    serving_size_pieces: []const u8,
    properties: []IngredientProperty,

    fn parseJson(alloc: std.mem.Allocator, lexer: *JsonLexer) !Ingredient {
        const lexer_cp = lexer.checkpoint();
        errdefer lexer.restore(lexer_cp);

        _ = try lexer.expectToken(.object_start);

        const IngredientProps = std.meta.FieldEnum(Ingredient);

        var id: ?[]const u8 = null;
        var name: ?[]const u8 = null;
        var serving_size_g: ?[]const u8 = null;
        var serving_size_ml: ?[]const u8 = null;
        var serving_size_pieces: ?[]const u8 = null;
        var properties: std.ArrayListUnmanaged(IngredientProperty) = .{};

        while (try lexer.objectKeyOrEnd()) |key_s| {
            const key = std.meta.stringToEnum(IngredientProps, key_s) orelse {
                try lexer.discardJsonValue();
                continue;
            };

            switch (key) {
                .id => id = try lexer.nextAsString(),
                .name => name = try lexer.nextAsString(),
                .serving_size_g => serving_size_g = try lexer.nextAsString(),
                .serving_size_ml => serving_size_ml = try lexer.nextAsString(),
                .serving_size_pieces => serving_size_pieces = try lexer.nextAsString(),
                .properties => {
                    _ = try lexer.expectToken(.array_start);
                    while (true) {
                        const property = IngredientProperty.parseJson(lexer) catch {
                            _ = try lexer.expectToken(.array_end);
                            break;
                        };
                        try properties.append(alloc, property);
                    }
                },
            }
        }

        return .{
            .id = id orelse return error.MissingField,
            .name = name orelse return error.MissingField,
            .serving_size_g = serving_size_g orelse return error.MissingField,
            .serving_size_ml = serving_size_ml orelse return error.MissingField,
            .serving_size_pieces = serving_size_pieces orelse return error.MissingField,
            .properties = properties.items,
        };
    }
};

pub export fn parse() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    var lexer = JsonLexer.init(wsr.getInputBuffer());
    const value = Ingredient.parseJson(arena.allocator(), &lexer) catch return;
    wsr.writeStdout(value.name);
}
