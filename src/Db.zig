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

typical_dish_dishes: usize = 100,
max_dish_dishes: usize = 10000,

typical_num_dishes: usize = 100,
max_num_dishes: usize = 10000,

// 3 years * 3 meals
typical_num_meals: usize = 1000,
// 100 years * 3 meals
max_num_meals: usize = 10000,

// Most times I eat 1 or a few things per meal
// e.g.
//   * Burger + fries + salad
//   * spaghetti w sauce
//   * egg on bread
// 10 is likely a huge overestimate
// 1000 is insane
typical_num_meal_dishes: usize = 3,
max_num_meal_dishes: usize = 1000,

// If I put 1000 ingredients in something, wtf am i doing?
max_num_meal_dish_ingredeints: usize = 1000,

// How many types of bread could I possibly buy?
// In reality probably ~3, 10 is an overestimate, 100 would be insane, 10x for
// safety
typical_category_ingredients: usize = 10,
max_category_ingredients: usize = 1000,

// Most things will be in one category, some might be in a few, 10x and round
// up to order of magnitude
typical_ingredient_category_mappings: usize = 1,
max_ingredient_category_mappings: usize = 100,

pub fn init(path: [:0]const u8) !Db {
    var db: ?*sqlite.sqlite3 = null;
    try cCheck(db, sqlite.sqlite3_open(path, &db));
    try cCheck(db, sqlite.sqlite3_exec(db, "PRAGMA foreign_keys = ON", null, null, null));

    var ret = Db{
        .db = db.?,
    };

    const app_version = 3;
    const version = try ret.userVersion();
    if (version > app_version) {
        return error.UnknownVersion;
    }

    const upgrade_funcs: []const *const fn (*Db) anyerror!void = &.{
        initv1,
        upgradeV1V2,
        upgradeV2V3,
    };

    if (version < upgrade_funcs.len) {
        for (upgrade_funcs[version..]) |f| {
            try f(&ret);
        }
    }

    const new_version = try ret.userVersion();
    std.debug.assert(new_version == app_version);

    return ret;
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
        .category_mappings = .empty,
    };
}

pub const IngredientProperty = struct {
    id: i64,
    ingredient_id: i64,
    property_id: i64,
    value: api.FixedPointNumber,
};

pub const IngredientCategoryMapping = struct {
    id: i64,
    ingredient_id: i64,
    ingredient_category_id: i64,
};

pub const Ingredient = struct {
    id: i64,
    name: []const u8,
    serving_size_g: i64,
    serving_size_ml: i64,
    serving_size_pieces: i64,
    category_mappings: sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping),
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
        .category_mappings = try self.getCategoriesForIngredient(leaky, id),
        .properties = try self.getIngredientProperties(leaky, id),
    };
}

fn getCategoriesForIngredient(self: *Db, leaky: std.mem.Allocator, ingredient_id: i64) !sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping) {
    const statement = try Statement.init(
        self,
        "SELECT id, category_id FROM ingredient_category_mapping WHERE ingredient_id = ?1 ORDER BY id;",
    );
    defer statement.deinit();

    try statement.bindi64(1, ingredient_id);

    var ret = try sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping).init(
        leaky,
        leaky,
        self.typical_ingredient_category_mappings,
        self.max_ingredient_category_mappings,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .ingredient_id = ingredient_id,
            .ingredient_category_id = try statement.geti64(1),
        });
    }

    return ret;
}

fn getIngredientProperties(self: *Db, leaky: std.mem.Allocator, ingredient_id: i64) !sphtud.util.RuntimeSegmentedList(IngredientProperty) {
    const statement = try Statement.init(
        self,
        "SELECT id, property_id, value FROM ingredient_properties WHERE ingredient_id = ?1 ORDER BY id;",
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
            .value = try statement.getFixedPointNum(2),
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
        const ingredient_id = try statement.geti64(0);
        try ret.append(.{
            .id = ingredient_id,
            .name = try statement.getText(leaky, 1),
            .serving_size_g = try statement.geti64(2),
            .serving_size_ml = try statement.geti64(3),
            .serving_size_pieces = try statement.geti64(4),
            .category_mappings = try self.getCategoriesForIngredient(leaky, ingredient_id),
        });
    }

    return ret;
}

pub const Property = struct {
    id: i64,
    name: []const u8,
    parent_id: ?i64,
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
        "SELECT id, name, parent_id FROM properties;",
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
            .parent_id = try statement.getOptionali64(2),
        });
    }

    return ret;
}

pub fn addProperty(self: *Db, params: api.AddProperty) !Property {
    const statement = try Statement.init(
        self,
        "INSERT INTO properties (name, parent_id) VALUES(?1, ?2);",
    );
    defer statement.deinit();

    try statement.bindText(1, params.name);

    if (params.parent_id) |parent_id| {
        try statement.bindi64(2, parent_id);
    } else {
        try statement.bindNull(2);
    }

    try statement.stepNoResult();
    const id = sqlite.sqlite3_last_insert_rowid(self.db);

    return .{
        .id = id,
        .name = params.name,
        .parent_id = params.parent_id,
    };
}

pub fn modifyProperty(self: *Db, id: i64, name: []const u8) !void {
    const statement = try Statement.init(
        self,
        "UPDATE properties SET name = ?2 WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindText(2, name);

    try statement.stepNoResult();
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
        .value = .fromFrac(0, 0),
    };
}

pub fn modifyIngredientProperty(self: *Db, id: i64, value: api.FixedPointNumber) !void {
    const statement = try Statement.init(
        self,
        "UPDATE ingredient_properties SET value = ?2 WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindInt(2, value.toDbRepr());

    try statement.stepNoResult();
}

pub fn deleteIngredientProperty(self: *Db, id: i64) !void {
    const statement = try Statement.init(
        self,
        "DELETE FROM ingredient_properties WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);

    try statement.stepNoResult();
}

pub const DishProperty = struct {
    property_id: i64,
    value: i64,
};

pub const Dish = struct {
    id: i64,
    name: []const u8,
};

pub fn addDish(self: *Db, name: []const u8) !Dish {
    const statement = try Statement.init(
        self,
        "INSERT INTO dishes (name) VALUES(?1)",
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

pub fn modifyDish(self: *Db, id: i64, name: []const u8) !void {
    const statement = try Statement.init(
        self,
        "UPDATE dishes SET name = ?2 WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindText(2, name);
    try statement.stepNoResult();
}

pub fn getDishes(self: *Db, leaky: std.mem.Allocator) !sphtud.util.RuntimeSegmentedList(Dish) {
    const statement = try Statement.init(self, "SELECT id, name FROM dishes;");
    defer statement.deinit();

    var ret = try sphtud.util.RuntimeSegmentedList(Dish).init(
        leaky,
        leaky,
        self.typical_num_dishes,
        self.max_num_dishes,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .name = try statement.getText(leaky, 1),
        });
    }

    return ret;
}

pub const PropertySummary = struct {
    property_id: i64,
    value: api.FixedPointNumber,
};

pub const Meal = struct {
    id: i64,
    timestamp_utc: i64,
    tz_offs_min: i64,
    dishes: sphtud.util.RuntimeSegmentedList(MealDish),
    summary: []PropertySummary,
};

pub fn addMeal(self: *Db, params: api.AddMealParams) !Meal {
    const statement = try Statement.init(
        self,
        "INSERT INTO meals (timestamp, tz_offs_min) VALUES (?1, ?2)",
    );
    defer statement.deinit();

    try statement.bindi64(1, params.timestamp_utc);
    try statement.bindi64(2, params.tz_offs_min);

    try statement.stepNoResult();
    return .{
        .id = sqlite.sqlite3_last_insert_rowid(self.db),
        .timestamp_utc = params.timestamp_utc,
        .tz_offs_min = params.tz_offs_min,
        .dishes = .empty,
        .summary = &.{},
    };
}

pub fn getMeal(self: *Db, leaky: std.mem.Allocator, scratch: sphtud.alloc.LinearAllocator, id: i64) !Meal {
    const statement = try Statement.init(
        self,
        "SELECT id, timestamp, tz_offs_min FROM meals WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);

    try statement.stepExpectRow();

    const timestamp = try statement.geti64(1);
    const tz_offs_min = try statement.geti64(2);

    return .{
        .id = id,
        .timestamp_utc = timestamp,
        .tz_offs_min = tz_offs_min,
        .dishes = try self.getMealDishes(leaky, id, .with_ingredients),
        .summary = try self.getMealSummary(leaky, scratch, id),
    };
}

pub fn deleteMeal(self: *Db, meal_id: i64) !void {
    // ON CASCADE ensures that this propagates to all relevant places
    const statement = try Statement.init(
        self,
        "DELETE FROM meals WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, meal_id);
    try statement.stepNoResult();
}

fn countTableEntries(db: *Db, comptime table: []const u8) !usize {
    var statement = try Statement.init(db, "SELECT COUNT(*) FROM " ++ table);
    defer statement.deinit();

    try statement.stepExpectRow();
    return @intCast(try statement.geti64(0));
}

test "deleteMeal cascade" {
    // Mostly covered by integration test, but here we want to ensure that the
    // database state is as expected, which is not visible in the API

    var db = try Db.init(":memory:");
    const meal = try db.addMeal(.{
        .timestamp_utc = 1234,
        .tz_offs_min = -420,
    });

    const dish = try db.addDish("dish");

    const meal_dish = try db.addMealDish(.{
        .meal_id = meal.id,
        .dish_id = dish.id,
    });

    const ingredient = try db.addIngredient("ingredient");

    _ = try db.addMealDishIngredient(.{
        .meal_dish_id = meal_dish.id,
        .ingredient_id = ingredient.id,
    });

    try std.testing.expectEqual(1, try countTableEntries(&db, "meals"));
    try std.testing.expectEqual(1, try countTableEntries(&db, "meal_dishes"));
    try std.testing.expectEqual(1, try countTableEntries(&db, "meal_dish_ingredients"));

    try db.deleteMeal(meal.id);

    try std.testing.expectEqual(0, try countTableEntries(&db, "meals"));
    try std.testing.expectEqual(0, try countTableEntries(&db, "meal_dishes"));
    try std.testing.expectEqual(0, try countTableEntries(&db, "meal_dish_ingredients"));
}

pub fn getMeals(self: *Db, leaky: std.mem.Allocator, scratch: sphtud.alloc.LinearAllocator) !sphtud.util.RuntimeSegmentedList(Meal) {
    const statement = try Statement.init(
        self,
        "SELECT id, timestamp, tz_offs_min FROM meals",
    );
    defer statement.deinit();

    var ret = try sphtud.util.RuntimeSegmentedList(Meal).init(
        leaky,
        leaky,
        self.typical_num_meals,
        self.max_num_meals,
    );

    while (try statement.step()) {
        const meal_id = try statement.geti64(0);
        try ret.append(.{
            .id = meal_id,
            .timestamp_utc = try statement.geti64(1),
            .tz_offs_min = try statement.geti64(2),
            .dishes = try self.getMealDishes(
                leaky,
                meal_id,
                .without_ingredients,
            ),
            .summary = try self.getMealSummary(leaky, scratch, meal_id),
        });
    }

    return ret;
}

fn ingredientById(ingredients: sphtud.util.RuntimeSegmentedList(Ingredient), id: i64) ?Ingredient {
    var it = ingredients.iter();
    while (it.next()) |ingredient| {
        if (ingredient.id == id) {
            return ingredient.*;
        }
    }

    return null;
}

fn getPropertyParentMappings(self: *Db, leaky: std.mem.Allocator) !std.AutoHashMap(i64, []i64) {
    const properties = try self.getProperties(leaky);

    var direct_parent_map = std.AutoHashMap(i64, ?i64).init(leaky);
    try direct_parent_map.ensureTotalCapacity(@intCast(properties.len));

    var property_it = properties.iter();
    while (property_it.next()) |property| {
        try direct_parent_map.put(property.id, property.parent_id);
    }

    var ret = std.AutoHashMap(i64, []i64).init(leaky);
    try ret.ensureTotalCapacity(@intCast(properties.len));

    property_it = properties.iter();
    while (property_it.next()) |property| {
        var parent_id = property.parent_id;
        var property_parent_list = try sphtud.util.RuntimeBoundedArray(i64).init(
            leaky,
            // 5 depth is crazy big. Surely no nutrition label would look like
            //
            // A
            //   B
            //     C
            //       D
            //         E
            //
            // REMINDER: If this is not true, post a photo on discord
            5,
        );

        try property_parent_list.append(property.id);
        while (parent_id) |pid| {
            try property_parent_list.append(pid);
            parent_id = direct_parent_map.get(pid) orelse unreachable;
        }
        try ret.put(property.id, property_parent_list.items);
    }

    return ret;
}

fn getMealSummary(self: *Db, leaky: std.mem.Allocator, scratch: sphtud.alloc.LinearAllocator, meal_id: i64) ![]PropertySummary {
    const checkpoint = scratch.checkpoint();
    defer scratch.restore(checkpoint);

    const statement = try Statement.init(self,
        \\SELECT mdi.quantity, mdi.unit, igp.value, igp.property_id, ig.serving_size_g, ig.serving_size_ml, ig.serving_size_pieces
        \\    FROM meal_dish_ingredients as mdi
        \\    LEFT JOIN ingredients as ig
        \\        ON ig.id == mdi.ingredient_id
        \\    CROSS JOIN ingredient_properties as igp
        \\        ON ig.id = igp.ingredient_id
        \\    WHERE mdi.meal_dish_id IN (
        \\        SELECT id FROM meal_dishes WHERE meal_id = ?1
        \\    )
    );
    defer statement.deinit();

    try statement.bindi64(1, meal_id);

    const property_parent_mappings = try self.getPropertyParentMappings(scratch.allocator());

    var property_id_to_total = std.AutoHashMap(i64, f32).init(scratch.allocator());
    try property_id_to_total.ensureTotalCapacity(@intCast(self.typical_ingredient_properties));

    while (try statement.step()) {
        const quantity: f32 = @floatFromInt(try statement.geti64(0));
        const unit = try statement.getUnitType(1);
        const serving_amount = try statement.getFixedPointNum(2);
        const property_id = try statement.geti64(3);

        // ingredient_id, quantity, unit
        const divisor = switch (unit) {
            .mass => try statement.geti64(4),
            .volume => try statement.geti64(5),
            .pieces => try statement.geti64(6),
        };

        const value = if (divisor == 0) -1 else serving_amount.toFloat() * quantity / @as(f32, @floatFromInt(divisor));

        const property_parent_list = property_parent_mappings.get(property_id) orelse unreachable;
        for (property_parent_list) |addition_id| {
            const gop = try property_id_to_total.getOrPut(addition_id);
            if (!gop.found_existing) {
                gop.value_ptr.* = 0;
            }

            if (value < 0) {
                gop.value_ptr.* = -1;
            } else {
                gop.value_ptr.* += value;
            }
        }
    }

    var it = property_id_to_total.iterator();
    var ret = try sphtud.util.RuntimeBoundedArray(PropertySummary).init(leaky, property_id_to_total.count());
    while (it.next()) |entry| {
        ret.append(.{
            .property_id = entry.key_ptr.*,
            .value = .fromf32(entry.value_ptr.*),
        }) catch unreachable;
    }
    return ret.items;
}

pub const MealDishIngredient = struct {
    id: i64,
    meal_dish_id: i64,
    ingredient_id: i64,
    quantity: i64,
    unit: api.UnitType,
};

pub const MealDish = struct {
    id: i64,
    meal_id: i64,
    dish_id: i64,
    ingredients: []MealDishIngredient,
};

pub fn addMealDish(self: *Db, params: api.AddMealDishParams) !MealDish {
    const statement = try Statement.init(
        self,
        "INSERT INTO meal_dishes (meal_id, dish_id) VALUES (?1, ?2)",
    );
    defer statement.deinit();

    try statement.bindi64(1, params.meal_id);
    try statement.bindi64(2, params.dish_id);

    try statement.stepNoResult();

    return .{
        .id = sqlite.sqlite3_last_insert_rowid(self.db),
        .meal_id = params.meal_id,
        .dish_id = params.dish_id,
        .ingredients = &.{},
    };
}

pub fn deleteMealDish(self: *Db, id: i64) !void {
    const statement = try Statement.init(
        self,
        "DELETE FROM meal_dishes WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.stepNoResult();
}

test "deleteMealDish cascade" {
    // Mostly covered by integration test, but here we want to ensure that the
    // database state is as expected, which is not visible in the API

    var db = try Db.init(":memory:");
    const meal = try db.addMeal(.{
        .timestamp_utc = 1234,
        .tz_offs_min = -420,
    });

    const dish = try db.addDish("dish");

    const meal_dish = try db.addMealDish(.{
        .meal_id = meal.id,
        .dish_id = dish.id,
    });

    const ingredient = try db.addIngredient("ingredient");

    _ = try db.addMealDishIngredient(.{
        .meal_dish_id = meal_dish.id,
        .ingredient_id = ingredient.id,
    });

    try std.testing.expectEqual(1, try countTableEntries(&db, "meal_dishes"));
    try std.testing.expectEqual(1, try countTableEntries(&db, "meal_dish_ingredients"));

    try db.deleteMealDish(meal_dish.id);

    try std.testing.expectEqual(0, try countTableEntries(&db, "meal_dishes"));
    try std.testing.expectEqual(0, try countTableEntries(&db, "meal_dish_ingredients"));
}

const GetMealDishType = enum {
    with_ingredients,
    without_ingredients,
};

pub fn getMealDishes(self: *Db, leaky: std.mem.Allocator, meal_id: i64, retrieveal_type: GetMealDishType) !sphtud.util.RuntimeSegmentedList(MealDish) {
    const statement = try Statement.init(
        self,
        "SELECT id, dish_id FROM meal_dishes WHERE meal_id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, meal_id);
    var ret = try sphtud.util.RuntimeSegmentedList(MealDish).init(
        leaky,
        leaky,
        self.typical_num_meal_dishes,
        self.max_num_meal_dishes,
    );

    while (try statement.step()) {
        const meal_dish_id = try statement.geti64(0);
        const ingredients: []MealDishIngredient = switch (retrieveal_type) {
            .with_ingredients => try self.getMealDishIngredients(leaky, meal_dish_id),
            .without_ingredients => &.{},
        };

        try ret.append(.{
            .id = meal_dish_id,
            .meal_id = meal_id,
            .dish_id = try statement.geti64(1),
            .ingredients = ingredients,
        });
    }

    return ret;
}

pub fn addMealDishIngredient(self: *Db, params: api.AddMealDishIngredientParams) !MealDishIngredient {
    const statement = try Statement.init(self,
        \\INSERT INTO meal_dish_ingredients
        \\    (meal_dish_id, ingredient_id, quantity, unit)
        \\    VALUES (?1, ?2, 0, 0);
    );
    defer statement.deinit();

    try statement.bindi64(1, params.meal_dish_id);
    try statement.bindi64(2, params.ingredient_id);

    try statement.stepNoResult();

    return .{
        .id = sqlite.sqlite3_last_insert_rowid(self.db),
        .meal_dish_id = params.meal_dish_id,
        .ingredient_id = params.ingredient_id,
        .quantity = 0,
        .unit = @enumFromInt(0),
    };
}

pub fn modifyMealDishIngredient(self: *Db, id: i64, params: api.ModifyMealDishIngredientParams) !void {
    const statement = try Statement.init(self,
        \\UPDATE meal_dish_ingredients
        \\    SET quantity = ?2, unit = ?3
        \\    WHERE id = ?1
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindi64(2, params.quantity);
    try statement.bindInt(3, @intFromEnum(params.unit));

    try statement.stepNoResult();
}

pub fn deleteMealDishIngredient(self: *Db, id: i64) !void {
    const statement = try Statement.init(
        self,
        "DELETE FROM  meal_dish_ingredients WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.stepNoResult();
}

const IngredientCategory = struct {
    id: i64,
    name: []const u8,
    // Only retrieved in specific page
    mappings: ?sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping),
};

pub fn addIngredientCategory(self: *Db, leaky: std.mem.Allocator, params: api.AddIngredientCategoryParams) !IngredientCategory {
    try cCheck(self.db, sqlite.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, null));
    errdefer {
        _ = sqlite.sqlite3_exec(self.db, "ROLLBACK TRANSACTION;", null, null, null);
    }

    // Add category
    {
        if (params.name) |name| {
            const statement = try Statement.init(
                self,
                "INSERT INTO ingredient_categories (name) VALUES (?1)",
            );
            defer statement.deinit();

            try statement.bindText(1, name);
            try statement.stepNoResult();
        } else if (params.ingredient_id) |ingredient_id| {
            const statement = try Statement.init(
                self,
                "INSERT INTO ingredient_categories (name) SELECT name FROM ingredients WHERE id = ?1",
            );
            defer statement.deinit();

            try statement.bindi64(1, ingredient_id);
            try statement.stepNoResult();
        } else unreachable;
    }

    const category_id = sqlite.sqlite3_last_insert_rowid(self.db);

    if (params.ingredient_id) |ingredient_id| {
        const statement = try Statement.init(
            self,
            "INSERT INTO ingredient_category_mapping (ingredient_id, category_id) VALUES (?1, ?2)",
        );
        defer statement.deinit();

        try statement.bindi64(1, ingredient_id);
        try statement.bindi64(2, category_id);
        try statement.stepNoResult();
    }

    try cCheck(self.db, sqlite.sqlite3_exec(self.db, "COMMIT TRANSACTION", null, null, null));

    return try self.getIngredientCategory(leaky, category_id);
}

pub fn getIngredientCategory(self: *Db, leaky: std.mem.Allocator, id: i64) !IngredientCategory {
    const statement = try Statement.init(
        self,
        "SELECT name FROM ingredient_categories WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);

    try statement.stepExpectRow();
    const name = try statement.getText(leaky, 0);

    return .{
        .id = id,
        .name = name,
        .mappings = try self.getIngredientCategoryIngredients(leaky, id),
    };
}

pub fn getIngredientCategories(self: *Db, leaky: std.mem.Allocator) !sphtud.util.RuntimeSegmentedList(IngredientCategory) {
    const statement = try Statement.init(
        self,
        "SELECT id, name FROM ingredient_categories",
    );
    defer statement.deinit();

    var ret = try sphtud.util.RuntimeSegmentedList(IngredientCategory).init(
        leaky,
        leaky,
        self.typical_num_ingredients,
        self.max_num_ingredients,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .name = try statement.getText(leaky, 1),
            .mappings = null,
        });
    }

    return ret;
}

pub fn modifyIngredientCategory(self: *Db, id: i64, params: api.ModifyIngredientCategoryParams) !void {
    const statement = try Statement.init(
        self,
        "UPDATE ingredient_categories SET name = ?2 WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);
    try statement.bindText(2, params.name);

    try statement.stepNoResult();
}

pub fn addIngredientCategoryMapping(self: *Db, params: api.AddIngredientCategoryMapping) !IngredientCategoryMapping {
    const statement = try Statement.init(
        self,
        "INSERT INTO ingredient_category_mapping (ingredient_id, category_id) VALUES (?1, ?2)",
    );
    defer statement.deinit();

    try statement.bindi64(1, params.ingredient_id);
    try statement.bindi64(2, params.category_id);

    try statement.stepNoResult();

    const id = sqlite.sqlite3_last_insert_rowid(self.db);

    return .{
        .id = id,
        .ingredient_id = params.ingredient_id,
        .ingredient_category_id = params.category_id,
    };
}

pub fn deleteIngredientCategoryMapping(self: *Db, id: i64) !void {
    const statement = try Statement.init(
        self,
        "DELETE FROM ingredient_category_mapping WHERE id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);

    try statement.stepNoResult();
}

pub fn getIngredientCategoryIngredients(self: *Db, leaky: std.mem.Allocator, id: i64) !sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping) {
    const statement = try Statement.init(
        self,
        "SELECT id, ingredient_id FROM ingredient_category_mapping WHERE category_id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, id);

    var ret = try sphtud.util.RuntimeSegmentedList(IngredientCategoryMapping).init(
        leaky,
        leaky,
        self.typical_category_ingredients,
        self.max_category_ingredients,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .ingredient_id = try statement.geti64(1),
            .ingredient_category_id = id,
        });
    }

    return ret;
}

pub fn copyMealDish(self: *Db, leaky: std.mem.Allocator, params: api.CopyMealDishParams) ![]MealDishIngredient {
    const statement = try Statement.init(self,
        \\INSERT INTO meal_dish_ingredients (meal_dish_id, ingredient_id, quantity, unit)
        \\SELECT ?2, ingredient_id, quantity, unit
        \\    FROM meal_dish_ingredients
        \\    WHERE meal_dish_id = ?1
    );
    defer statement.deinit();

    try statement.bindi64(1, params.from_meal_dish_id);
    try statement.bindi64(2, params.to_meal_dish_id);

    try statement.stepNoResult();

    return self.getMealDishIngredients(leaky, params.to_meal_dish_id);
}

pub fn getMealDishIngredients(self: *Db, leaky: std.mem.Allocator, meal_dish_id: i64) ![]MealDishIngredient {
    const statement = try Statement.init(
        self,
        "SELECT id, ingredient_id, quantity, unit FROM meal_dish_ingredients WHERE meal_dish_id = ?1",
    );
    defer statement.deinit();

    try statement.bindi64(1, meal_dish_id);
    var ret = try sphtud.util.RuntimeBoundedArray(MealDishIngredient).init(
        leaky,
        self.max_num_meal_dish_ingredeints,
    );

    while (try statement.step()) {
        try ret.append(.{
            .id = try statement.geti64(0),
            .meal_dish_id = meal_dish_id,
            .ingredient_id = try statement.geti64(1),
            .quantity = try statement.geti64(2),
            .unit = try statement.getUnitType(3),
        });
    }

    return ret.items;
}

const Statement = struct {
    inner: *sqlite.sqlite3_stmt,
    db: *Db,

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
            .db = db,
        };
    }

    fn deinit(self: Statement) void {
        _ = sqlite.sqlite3_finalize(self.inner);
    }

    fn bindInt(self: Statement, column: c_int, val: c_int) !void {
        try cCheck(self.db.db, sqlite.sqlite3_bind_int(self.inner, column, val));
    }

    fn bindi64(self: Statement, column: c_int, val: i64) !void {
        try cCheck(self.db.db, sqlite.sqlite3_bind_int64(self.inner, column, val));
    }

    fn bindNull(self: Statement, column: c_int) !void {
        try cCheck(self.db.db, sqlite.sqlite3_bind_null(
            self.inner,
            column,
        ));
    }

    fn bindText(self: Statement, column: c_int, val: []const u8) !void {
        try cCheck(self.db.db, sqlite.sqlite3_bind_text(
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

    fn getOptionali64(self: Statement, column: c_int) !?i64 {
        const t = sqlite.sqlite3_column_type(self.inner, column);
        if (t == sqlite.SQLITE_NULL) return null;
        return sqlite.sqlite3_column_int64(self.inner, column);
    }

    fn getFixedPointNum(self: Statement, column: c_int) !api.FixedPointNumber {
        const ret = sqlite.sqlite3_column_int(self.inner, column);
        return api.FixedPointNumber.fromDbRepr(ret);
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
        try cCheck(self.db.db, ret);
    }
};

fn cCheck(db: ?*sqlite.sqlite3, ret: c_int) !void {
    const err = switch (ret) {
        0, sqlite.SQLITE_DONE => return,
        sqlite.SQLITE_CONSTRAINT => error.SqliteConstraint,
        else => error.Sqlite,
    };

    if (sqlite.sqlite3_errmsg(db)) |msg| {
        std.log.err("sqlite error: \"{s}\"", .{msg});
    }

    return err;
}

fn userVersion(db: *Db) !usize {
    const statement = try Statement.init(
        db,
        "PRAGMA user_version",
    );
    defer statement.deinit();

    try statement.stepExpectRow();
    const ret = try statement.geti64(0);
    if (ret < 0) {
        return error.InvalidVersion;
    }
    return @intCast(ret);
}

fn initv1(db: *Db) !void {
    try cCheck(db.db, sqlite.sqlite3_exec(
        db.db,
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
        \\    FOREIGN KEY(ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE,
        \\    FOREIGN KEY(property_id) REFERENCES properties(id) ON DELETE CASCADE,
        \\    UNIQUE(ingredient_id, property_id)
        \\);
        \\CREATE TABLE IF NOT EXISTS dishes(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT UNIQUE NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS meals(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    timestamp INTEGER NOT NULL,
        \\    tz_offs_min INTEGER NOT NULL
        \\);
        \\CREATE TABLE IF NOT EXISTS meal_dishes(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    meal_id INTEGER NOT NULL,
        \\    dish_id INTEGER NOT NULL,
        \\    FOREIGN KEY(meal_id) REFERENCES meals(id) ON DELETE CASCADE,
        \\    FOREIGN KEY(dish_id) REFERENCES dishes(id) ON DELETE CASCADE,
        \\    UNIQUE(meal_id, dish_id)
        \\);
        \\CREATE TABLE IF NOT EXISTS meal_dish_ingredients(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    meal_dish_id INTEGER NOT NULL,
        \\    ingredient_id INTEGER NOT NULL,
        \\    quantity INTEGER NOT NULL,
        \\    unit INTEGER NOT NULL,
        \\    FOREIGN KEY(meal_dish_id) REFERENCES meal_dishes(id) ON DELETE CASCADE,
        \\    FOREIGN KEY(ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE,
        \\    UNIQUE(meal_dish_id, ingredient_id)
        \\);
    ,
        null,
        null,
        null,
    ));

    try db.upgradeV0V1();
}

fn upgradeV0V1(db: *Db) !void {
    try cCheck(db.db, sqlite.sqlite3_exec(
        db.db,
        \\ALTER TABLE properties ADD COLUMN parent_id INTEGER DEFAULT NULL REFERENCES properties(id) ON DELETE CASCADE;
        \\PRAGMA user_version = 1;
    ,
        null,
        null,
        null,
    ));
}

fn upgradeV1V2(db: *Db) !void {
    try cCheck(db.db, sqlite.sqlite3_exec(
        db.db,
        \\CREATE TABLE ingredient_categories(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    name TEXT UNIQUE NOT NULL
        \\);
        \\CREATE TABLE ingredient_category_mapping(
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
        \\    category_id INTEGER NOT NULL REFERENCES ingredient_categories(id) ON DELETE CASCADE,
        \\    UNIQUE(ingredient_id, category_id)
        \\);
        \\PRAGMA user_version = 2;
    ,
        null,
        null,
        null,
    ));
}

fn upgradeV2V3(db: *Db) !void {
    try cCheck(db.db, sqlite.sqlite3_exec(
        db.db,
        \\ALTER TABLE ingredients ADD COLUMN fully_entered INTEGER NOT NULL DEFAULT 0;
        \\PRAGMA user_version = 3;
    ,
        null,
        null,
        null,
    ));
}
