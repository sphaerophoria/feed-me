const std = @import("std");

const TokenType = enum {
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

pub const Lexer = struct {
    content: []const u8,
    idx: usize = 0,

    const Output = struct {
        token_type: TokenType,
        start: usize,
        end: usize,

        fn content(self: Output, buf: []const u8) []const u8 {
            switch (self.token_type) {
                .string => return buf[self.start + 1 .. self.end - 1],
                else => return buf[self.start..self.end],
            }
        }
    };

    pub fn init(content: []const u8) Lexer {
        return .{
            .content = content,
        };
    }

    pub fn next(self: *Lexer) ?Output {
        self.consumeWhitespace();
        return self.scanValue();
    }

    pub fn expectToken(self: *Lexer, token: TokenType) !Output {
        const res = self.next() orelse return error.NoToken;
        if (res.token_type != token) {
            return error.UnexpectedToken;
        }
        return res;
    }

    pub fn objectKeyOrEnd(self: *Lexer) !?[]const u8 {
        const key_or_end = self.next() orelse return error.NoToken;
        switch (key_or_end.token_type) {
            .object_end => return null,
            .string => {},
            else => return error.InvalidKey,
        }
        _ = try self.expectToken(.colon);
        return key_or_end.content(self.content);
    }

    pub fn parseListGrowable(lexer: *Lexer, comptime T: type, ctx: anytype, alloc: std.mem.Allocator) !std.ArrayList(T) {
        _ = try lexer.expectToken(.array_start);

        var elems = std.ArrayList(T).init(alloc);
        errdefer elems.deinit();

        while (true) {
            const elem = ctx.parse(lexer) catch |e| {
                _ = lexer.expectToken(.array_end) catch return e;
                break;
            };

            try elems.append(elem);
        }

        return elems;
    }

    pub fn parseList(self: *Lexer, comptime T: type, ctx: anytype, alloc: std.mem.Allocator) ![]T {
        var ret = try self.parseListGrowable(T, ctx, alloc);
        defer ret.deinit();

        return try ret.toOwnedSlice();
    }

    pub fn discardValue(lexer: *Lexer) !void {
        const start = lexer.next() orelse return error.NoValue;
        switch (start.token_type) {
            .object_start => try discardObject(lexer),
            .array_start => try discardArray(lexer),
            .colon, .string, .number, .true, .false, .null => return,
            .array_end, .object_end, .invalid => return error.InvalidValue,
        }
    }

    pub fn discardObject(lexer: *Lexer) anyerror!void {
        while (true) {
            const key_or_end = lexer.next() orelse return error.UnfinishedObject;
            switch (key_or_end.token_type) {
                .object_end => return,
                .string => {},
                else => return error.UnexpectedToken,
            }
            _ = try lexer.expectToken(.colon);
            try discardValue(lexer);
        }
    }

    pub fn discardArray(lexer: *Lexer) !void {
        while (true) {
            const start = lexer.next() orelse return error.NoValue;
            switch (start.token_type) {
                .object_start => try discardObject(lexer),
                .array_start => try discardArray(lexer),
                .array_end => return,
                .string, .number, .true, .false, .null => continue,
                .object_end, .colon, .invalid => return error.InvalidValue,
            }
        }
    }

    pub fn nextAsString(self: *Lexer) ![]const u8 {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .string => {},
            .number => {},
            else => return error.InvalidType,
        }

        return res.content(self.content);
    }

    pub fn nextAsStringCopy(self: *Lexer, alloc: std.mem.Allocator) ![]const u8 {
        const s = try self.nextAsString();
        return try alloc.dupe(u8, s);
    }

    pub fn nextAsInt(self: *Lexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseInt(T, res.content(self.content), 0);
    }

    pub fn nextAsFloat(self: *Lexer, comptime T: type) !T {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .number => {},
            else => return error.InvalidType,
        }

        return try std.fmt.parseFloat(T, res.content(self.content));
    }

    pub fn nextAsBool(self: *Lexer) !bool {
        const res = self.next() orelse return error.NoValue;
        switch (res.token_type) {
            .true => return true,
            .false => return false,
            else => return error.InvalidType,
        }
    }

    pub fn checkpoint(self: Lexer) usize {
        return self.idx;
    }

    pub fn restore(self: *Lexer, restore_point: usize) void {
        self.idx = restore_point;
    }

    fn consumeWhitespace(self: *Lexer) void {
        const ws_chars = [_]u8{ 0x20, 0x0A, 0x0D, 0x09, ',' };
        self.idx = std.mem.indexOfNonePos(u8, self.content, self.idx, &ws_chars) orelse self.content.len;
    }

    const ScanResult = struct {
        const invalid: ScanResult = .{ .token = .invalid, .consumed_bytes = 0 };

        token: TokenType,
        consumed_bytes: usize,
    };

    fn scanValue(self: *Lexer) ?Output {
        if (self.idx >= self.content.len) return null;
        const scan_res: ScanResult = switch (self.content[self.idx]) {
            '{' => .{ .token = TokenType.object_start, .consumed_bytes = 1 },
            '}' => .{ .token = TokenType.object_end, .consumed_bytes = 1 },
            '[' => .{ .token = TokenType.array_start, .consumed_bytes = 1 },
            ']' => .{ .token = TokenType.array_end, .consumed_bytes = 1 },
            ':' => .{ .token = TokenType.colon, .consumed_bytes = 1 },
            '"' => self.scanStringEnd(),
            't' => self.scanTrue(),
            'f' => self.scanFalse(),
            'n' => self.scanNull(),
            '0'...'9' => self.scanNumber(),
            else => .{ .token = TokenType.invalid, .consumed_bytes = 0 },
        };

        defer self.idx += scan_res.consumed_bytes;

        return .{
            .token_type = scan_res.token,
            .start = self.idx,
            .end = self.idx + scan_res.consumed_bytes,
        };
    }

    fn scanStringEnd(self: *Lexer) ScanResult {
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

    fn scanIdentifier(self: *Lexer, comptime ident: []const u8, comptime on_match: TokenType) ScanResult {
        if (self.idx + ident.len > self.content.len) {
            return .invalid;
        }

        if (std.mem.eql(u8, self.content[self.idx .. self.idx + ident.len], ident)) {
            return .{
                .token = on_match,
                .consumed_bytes = ident.len,
            };
        }

        return .invalid;
    }

    fn scanTrue(self: *Lexer) ScanResult {
        return self.scanIdentifier("true", .true);
    }

    fn scanFalse(self: *Lexer) ScanResult {
        return self.scanIdentifier("false", .false);
    }

    fn scanNull(self: *Lexer) ScanResult {
        return self.scanIdentifier("null", .null);
    }

    fn scanNumber(self: *Lexer) ScanResult {
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
