const std = @import("std");
const sphtud = @import("sphtud");

pub const AddIngredient = struct {
    name: []const u8,

    pub fn validate(self: AddIngredient) !void {
        if (self.name.len == 0) {
            return error.InvalidName;
        }
    }
};

pub const AddProperty = struct {
    name: []const u8,

    pub fn validate(self: AddProperty) !void {
        if (self.name.len == 0) return error.InvalidName;
    }
};

pub const AddIngredientPropertyParams = struct {
    ingredient_id: i64,
    property_id: i64,
};

pub const ModifyIngredientPropertyParams = struct {
    value: i64,

    pub fn validate(self: ModifyIngredientPropertyParams) !void {
        if (self.value < 0) return error.InvalidValue;
    }
};

pub const ModifyIngredientParams = struct {
    name: ?[]const u8 = null,
    serving_size_g: ?i64 = null,
    serving_size_ml: ?i64 = null,
    serving_size_pieces: ?i64 = null,

    pub fn validate(self: ModifyIngredientParams) !void {
        if (self.name) |name| {
            if (name.len == 0) {
                return error.InvalidName;
            }
        }

        if (self.serving_size_g) |ss| {
            if (ss < 0) return error.InvalidServingSize;
        }

        if (self.serving_size_ml) |ss| {
            if (ss < 0) return error.InvalidServingSize;
        }

        if (self.serving_size_pieces) |ss| {
            if (ss < 0) return error.InvalidServingSize;
        }
    }
};

pub const AddDishParams = struct {
    name: []const u8,

    pub fn validate(self: AddDishParams) !void {
        if (self.name.len == 0) return error.InvalidName;
    }
};

pub const AddMealParams = struct {
    timestamp_utc: i64,
    tz_offs_min: i64,
};

pub const AddMealDishParams = struct {
    meal_id: i64,
    dish_id: i64,
};

pub const AddMealDishIngredientParams = struct {
    meal_dish_id: i64,
    ingredient_id: i64,
};

pub const ModifyMealDishIngredientParams = struct {
    quantity: i64,
    unit: UnitType,

    pub fn validate(self: ModifyMealDishIngredientParams) !void {
        if (self.quantity < 0) return error.InvalidQuantity;
    }
};

pub const Target = union(enum) {
    add_ingredient,
    get_ingredients,
    get_ingredient: i64,
    get_properties,
    add_property,
    modify_ingredient: i64,
    add_ingredient_property,
    modify_ingredient_property: i64,
    add_dish,
    get_dishes,
    redirect_to_index,
    add_meal,
    get_meals,
    get_meal: i64,
    add_meal_dish,
    add_meal_dish_ingredient,
    modify_meal_dish_ingredient: i64,
    memory_usage,
    filesystem: []const u8,

    pub fn parse(target: []const u8, method: std.http.Method) !Target {
        if (std.mem.eql(u8, target, "/")) {
            return .redirect_to_index;
        }

        var it = sphtud.http.url.UriIter.init(target);

        const Api = enum {
            ingredients,
            properties,
            ingredient_properties,
            dishes,
            meals,
            meal_dishes,
            meal_dish_ingredients,
            memory,
        };

        const maybe_api = it.next(Api) orelse unreachable;
        const api = switch (maybe_api) {
            .match => |api| api,
            .not_match => {
                return .{ .filesystem = target };
            },
        };

        const maybe_id = it.next(i64) orelse {
            switch (method) {
                .GET => {
                    switch (api) {
                        .ingredients => return .get_ingredients,
                        .properties => return .get_properties,
                        .dishes => return .get_dishes,
                        .meals => return .get_meals,
                        .memory => return .memory_usage,
                        else => return error.UnhandledMethod,
                    }
                },
                .PUT => {
                    switch (api) {
                        .ingredients => return .add_ingredient,
                        .properties => return .add_property,
                        .dishes => return .add_dish,
                        .ingredient_properties => return .add_ingredient_property,
                        .meals => return .add_meal,
                        .meal_dishes => return .add_meal_dish,
                        .meal_dish_ingredients => return .add_meal_dish_ingredient,
                        else => return error.UnhandledMethod,
                    }
                },
                else => return error.UnhandledMethod,
            }
        };

        const id = switch (maybe_id) {
            .match => |id| id,
            .not_match => return error.UnhandledMethod,
        };

        switch (method) {
            .GET => {
                switch (api) {
                    .ingredients => return .{ .get_ingredient = id },
                    .meals => return .{ .get_meal = id },
                    else => return error.UnhandledMethod,
                }
            },
            .PUT => {
                switch (api) {
                    .ingredients => return .{ .modify_ingredient = id },
                    .ingredient_properties => return .{ .modify_ingredient_property = id },
                    .meal_dish_ingredients => return .{ .modify_meal_dish_ingredient = id },
                    else => return error.UnhandledMethod,
                }
            },
            else => return error.UnhandledMethod,
        }
    }
};

pub const UnitType = enum(u8) {
    // DO NOT REORDER, STORED IN DB
    mass = 0,
    volume = 1,
    pieces = 2,
};
