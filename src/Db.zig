const std = @import("std");
const sphtud = @import("sphtud");
const api = @import("api.zig");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const Db = @This();

db: *sqlite.sqlite3,

typical_ingredient_properties: usize = 20,
max_ingredient_properties: usize = 100,

typical_num_ingredients: usize = 100,
max_num_ingredients: usize = 10000,

pub fn init(path: [:0]const u8) !Db {
    var db: ?*sqlite.sqlite3 = null;
    try cCheck(db, sqlite.sqlite3_open(path, &db));

    try cCheck(db, sqlite.sqlite3_exec(
        db,
        \\CREATE TABLE IF NOT EXISTS ingredients(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT UNIQUE NOT NULL,
        \\    serving_size_g INTEGER NOT NULL,
        \\    serving_size_ml INTEGER NOT NULL,
        \\    serving_size_pieces INTEGER NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS properties(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT UNIQUE NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS ingredient_properties(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    ingredient_id INTEGER NOT NULL,
        \\    property_id INTEGER NOT NULL,
        \\    value INTEGER NOT NULL,
        \\    FOREIGN KEY(ingredient_id) REFERENCES ingredients(id),
        \\    FOREIGN KEY(property_id) REFERENCES properties(id),
        \\    UNIQUE(ingredient_id, property_id)
        \\);
    ,
        null,
        null,
        null,
    ));

    return .{
        .db = db.?,
    };
}

pub fn deinit(self: *Db) void {
    _ = sqlite.sqlite3_close(self.db);
}

pub fn addIngredient(self: *Db, name: []const u8) !Ingredient {
    const statement = try Statement.init(
        self,
        "INSERT INTO ingredients (name, serving_size_g, serving_size_ml, serving_size_pieces) VALUES(?1, 0, 0, 0);",
    );
    defer statement.deinit();

    try statement.bindText(1, name);

    try statement.stepNoResult();

    const id = sqlite.sqlite3_last_insert_rowid(self.db);
    return .{
        .id = id,
        .name = name,
        .serving_size_g = 0,
        .serving_size_ml = 0,
        .serving_size_pieces = 0,
    };
}

pub const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    value: i64,
};

pub const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: i64,
    serving_size_ml: i64,
    serving_size_pieces: i64,
    // Only set on individual ingredient return
    properties: ?sphtud.util.RuntimeSegmentedList(IngredientProperty) = null,
};

pub fn getIngredient(self: *Db, id: i64, leaky: std.mem.Allocator) !Ingredient {
    const statement = try Statement.init(
        self,
        "SELECT name, serving_size_g, serving_size_ml, serving_size_pieces FROM ingredients WHERE id = ?1;",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.stepExpectRow();

    return .{
        .id = id,
        .name = try statement.getText(leaky, 0),
        .serving_size_g = try statement.geti64(1),
        .serving_size_ml = try statement.geti64(2),
        .serving_size_pieces = try statement.geti64(3),
        .properties = try self.getIngredientProperties(leaky, id),
    };
}

fn getIngredientProperties(self: *Db, leaky: std.mem.Allocator, ingredient_id: i64) !sphtud.util.RuntimeSegmentedList(IngredientProperty) {
    const statement = try Statement.init(
        self,
        "SELECT id, property_id, value FROM ingredient_properties WHERE ingredient_id = ?1;",
    );
    defer statement.deinit();

    try statement.bindi64(1, ingredient_id);

    var ret = try sphtud.util.RuntimeSegmentedList(IngredientProperty).init(
        leaky,
        leaky,
        self.typical_ingredient_properties,
        self.max_ingredient_properties,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .ingredient_id = ingredient_id,
            .property_id = try statement.geti64(1),
            .value = try statement.geti64(2),
        });
    }

    return ret;
}

pub fn getIngredients(self: *Db, leaky: std.mem.Allocator) !sphtud.util.RuntimeSegmentedList(Ingredient) {
    const statement = try Statement.init(
        self,
        "SELECT id, name, serving_size_g, serving_size_ml, serving_size_pieces FROM ingredients;",
    );
    defer statement.deinit();

    var ret = try sphtud.util.RuntimeSegmentedList(Ingredient).init(
        leaky,
        leaky,
        self.typical_num_ingredients,
        self.max_num_ingredients,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .name = try statement.getText(leaky, 1),
            .serving_size_g = try statement.geti64(2),
            .serving_size_ml = try statement.geti64(3),
            .serving_size_pieces = try statement.geti64(4),
        });
    }

    return ret;
}

pub const Property = struct {
    id: i64,
    name: []const u8,
};

const SetParamsBuilder = struct {
    sql: *sphtud.util.RuntimeBoundedArray(u8),
    first: bool = true,

    fn appendItem(self: *SetParamsBuilder, key: []const u8, bind_id: c_int) !void {
        var w = self.sql.writer();

        if (self.first) {
            try w.print("{s} = ?{d}", .{ key, bind_id });
        } else {
            try w.print(", {s} = ?{d}", .{ key, bind_id });
        }

        self.first = false;
    }
};

pub fn modifyIngredient(self: *Db, leaky: std.mem.Allocator, id: i64, params: api.ModifyIngredientParams) !Ingredient {
    var sql_buf: [1000]u8 = undefined;
    var sql = sphtud.util.RuntimeBoundedArray(u8).fromBuf(&sql_buf);

    try sql.appendSlice("UPDATE ingredients SET ");

    var set_params_builder = SetParamsBuilder{ .sql = &sql };

    if (params.name) |_| {
        try set_params_builder.appendItem("name", 2);
    }

    if (params.serving_size_g) |_| {
        try set_params_builder.appendItem("serving_size_g", 3);
    }

    if (params.serving_size_ml) |_| {
        try set_params_builder.appendItem("serving_size_ml", 4);
    }

    if (params.serving_size_pieces) |_| {
        try set_params_builder.appendItem("serving_size_pieces", 5);
    }

    if (set_params_builder.first) {
        return error.NoParams;
    }

    try sql.appendSlice(" WHERE id = ?1;");

    const statement = try Statement.init(self, sql.items);
    defer statement.deinit();

    try statement.bindi64(1, id);

    if (params.name) |name| try statement.bindText(2, name);
    if (params.serving_size_g) |g| try statement.bindi64(3, g);
    if (params.serving_size_ml) |ml| try statement.bindi64(4, ml);
    if (params.serving_size_pieces) |pieces| try statement.bindi64(5, pieces);

    try statement.stepNoResult();

    return try self.getIngredient(id, leaky);
}

pub fn getProperties(self: *Db, leaky: std.mem.Allocator) !sphtud.util.RuntimeSegmentedList(Property) {
    const statement = try Statement.init(
        self,
        "SELECT id, name FROM properties;",
    );
    defer statement.deinit();

    var ret = try sphtud.util.RuntimeSegmentedList(Property).init(
        leaky,
        leaky,
        self.typical_num_ingredients,
        self.max_num_ingredients,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .name = try statement.getText(leaky, 1),
        });
    }

    return ret;
}

pub fn addProperty(self: *Db, name: []const u8) !Property {
    const statement = try Statement.init(
        self,
        "INSERT INTO properties (name) VALUES(?1);",
    );
    defer statement.deinit();

    try statement.bindText(1, name);

    try statement.stepNoResult();
    const id = sqlite.sqlite3_last_insert_rowid(self.db);

    return .{
        .id = id,
        .name = name,
    };
}

pub fn addIngredientProperty(self: *Db, params: api.AddIngredientPropertyParams) !IngredientProperty {
    const statement = try Statement.init(
        self,
        "INSERT INTO ingredient_properties (ingredient_id, property_id, value) VALUES(?1, ?2, 0)",
    );
    defer statement.deinit();

    try statement.bindi64(1, params.ingredient_id);
    try statement.bindi64(2, params.property_id);

    try statement.stepNoResult();

    return .{
        .id = sqlite.sqlite3_last_insert_rowid(self.db),
        .ingredient_id = params.ingredient_id,
        .property_id = params.property_id,
        .value = 0,
    };
}

pub fn modifyIngredientProperty(self: *Db, id: i64, value: i64) !void {
    const statement = try Statement.init(
        self,
        "UPDATE ingredient_properties SET value = ?2 WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindi64(2, value);

    try statement.stepNoResult();
}

const Statement = struct {
    inner: *sqlite.sqlite3_stmt,

    fn init(db: *Db, sql: []const u8) !Statement {
        var statement: ?*sqlite.sqlite3_stmt = null;
        try cCheck(db.db, sqlite.sqlite3_prepare_v2(
            db.db,
            sql.ptr,
            @intCast(sql.len),
            &statement,
            null,
        ));

        return .{
            .inner = statement orelse unreachable,
        };
    }

    fn deinit(self: Statement) void {
        _ = sqlite.sqlite3_finalize(self.inner);
    }

    fn bindInt(self: Statement, column: c_int, val: c_int) !void {
        try cCheckNoMsg(sqlite.sqlite3_bind_int(self.inner, column, val));
    }

    fn bindi64(self: Statement, column: c_int, val: i64) !void {
        try cCheckNoMsg(sqlite.sqlite3_bind_int64(self.inner, column, val));
    }

    fn bindText(self: Statement, column: c_int, val: []const u8) !void {
        try cCheckNoMsg(sqlite.sqlite3_bind_text(
            self.inner,
            column,
            val.ptr,
            @intCast(val.len),
            sqlite.SQLITE_STATIC,
        ));
    }

    fn geti64(self: Statement, column: c_int) !i64 {
        return sqlite.sqlite3_column_int64(self.inner, column);
    }

    fn getInt(self: Statement, column: c_int) !c_int {
        return sqlite.sqlite3_column_int(self.inner, column);
    }

    fn getText(self: Statement, alloc: std.mem.Allocator, column: c_int) ![]const u8 {
        const name = sqlite.sqlite3_column_text(self.inner, column);
        const name_len = sqlite.sqlite3_column_bytes(self.inner, column);
        return try alloc.dupe(u8, name[0..@intCast(name_len)]);
    }

    fn getUnitType(statement: Statement, column: c_int) !api.UnitType {
        const unit_int = try statement.getInt(column);
        const unit = std.meta.intToEnum(api.UnitType, unit_int);
        return unit catch return error.InvalidUnit;
    }

    const StepResult = enum {
        row,
        done,
    };

    fn step(self: Statement) !bool {
        const ret = sqlite.sqlite3_step(self.inner);
        return switch (ret) {
            sqlite.SQLITE_DONE => false,
            sqlite.SQLITE_ROW => true,
            else => {
                return error.UnexpectedStatmenetBehavior;
            },
        };
    }

    fn stepExpectRow(self: Statement) !void {
        const res = try self.step();
        if (!res) return error.NoRow;
    }

    fn stepNoResult(self: Statement) !void {
        const ret = sqlite.sqlite3_step(self.inner);
        try cCheckNoMsg(ret);
    }
};

fn cCheckNoMsg(ret: c_int) !void {
    switch (ret) {
        0 => {},
        sqlite.SQLITE_DONE => {},
        sqlite.SQLITE_CONSTRAINT => return error.SqliteConstraint,
        else => return error.Sqlite,
    }
}

fn cCheck(db: ?*sqlite.sqlite3, ret: c_int) !void {
    if (ret != 0) {
        if (sqlite.sqlite3_errmsg(db)) |msg| {
            std.log.err("sqlite error: \"{s}\"", .{msg});
        }
        return error.Sqlite;
    }
}
