const std = @import("std");
const sphtud = @import("sphtud");
const json = @import("json.zig");

pub const Property = struct {
    name: []const u8,
    parent_id: ?i64,
};

pub const Properties = struct {
    pub const ChildMap = std.AutoHashMap(i64, std.ArrayList(i64));
    pub const PropertyMap = std.AutoArrayHashMap(i64, Property);

    items: PropertyMap,
    child_map: ChildMap,

    pub fn parse(alloc: std.mem.Allocator, data: []const u8) !Properties {
        const properties = try parseProperties(alloc, data);
        const child_map = try buildChildMap(alloc, &properties);

        return .{
            .items = properties,
            .child_map = child_map,
        };
    }

    pub const Iter = struct {
        root_it: PropertyMap.Iterator,
        it_stack: std.ArrayList(StackElem),
        parent: *const Properties,

        const StackElem = struct {
            items: []const i64,
            idx: usize,
        };

        pub const PropertyElem = struct {
            id: i64,
            name: []const u8,
        };

        pub const Output = union(enum) {
            level: PropertyElem,
            indent_up: PropertyElem,
            indent_down,
        };

        pub fn next(self: *Iter) !?Output {
            if (self.it_stack.items.len == 0) {
                while (true) {
                    const next_entry = self.root_it.next() orelse return null;

                    if (next_entry.value_ptr.parent_id != null) {
                        continue;
                    }

                    if (self.parent.child_map.get(next_entry.key_ptr.*)) |children| {
                        try self.it_stack.append(.{
                            .items = children.items,
                            .idx = 0,
                        });
                    }
                    return .{ .level = .{
                        .id = next_entry.key_ptr.*,
                        .name = next_entry.value_ptr.name,
                    } };
                }
            }

            var stack_elem = &self.it_stack.items[self.it_stack.items.len - 1];

            if (stack_elem.idx >= stack_elem.items.len) {
                _ = self.it_stack.pop();
                return .indent_down;
            }

            defer stack_elem.idx += 1;

            const next_elem_id = stack_elem.items[stack_elem.idx];
            const next_elem = self.parent.items.get(next_elem_id) orelse return error.MissingElem;

            if (self.parent.child_map.get(next_elem_id)) |children| {
                try self.it_stack.append(.{
                    .items = children.items,
                    .idx = 0,
                });
            }

            const ret_elem = PropertyElem{
                .id = next_elem_id,
                .name = next_elem.name,
            };

            if (stack_elem.idx == 0) {
                return .{ .indent_up = ret_elem };
            } else {
                return .{ .level = ret_elem };
            }
        }
    };

    pub fn iter(self: *const Properties, alloc: std.mem.Allocator) Iter {
        return .{
            .root_it = self.items.iterator(),
            .it_stack = std.ArrayList(Iter.StackElem).init(alloc),
            .parent = self,
        };
    }

    fn parseProperty(alloc: std.mem.Allocator, lexer: *json.Lexer, out: *PropertyMap) !void {
        const cp = lexer.checkpoint();
        errdefer lexer.restore(cp);

        _ = try lexer.expectToken(.object_start);

        var id: ?i64 = null;
        var name: ?[]const u8 = null;
        var parent_id: ?i64 = null;

        const Fields = enum { id, name, parent_id };

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

    fn parseProperties(alloc: std.mem.Allocator, data: []const u8) !std.AutoArrayHashMap(i64, Property) {
        var lexer = json.Lexer.init(data);

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
};
