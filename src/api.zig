const std = @import("std");
const sphtud = @import("sphtud");

pub const FixedPointNumber = packed struct(u32) {
    integer: u22,

    // 10^-3
    // 999 = 0.999
    fractional: u10,

    pub fn fromf32(val: f32) FixedPointNumber {
        return .{
            .integer = @intFromFloat(@trunc(val)),
            .fractional = @intFromFloat(@round(@mod(val, 1.0) * 1000)),
        };
    }

    pub fn fromFrac(integer: u22, fractional: u10) FixedPointNumber {
        std.debug.assert(fractional < 1000);
        return .{
            .integer = integer,
            .fractional = fractional,
        };
    }

    pub fn fromDbRepr(val: i32) !FixedPointNumber {
        const ret: FixedPointNumber = @bitCast(val);
        if (ret.fractional >= 1000) {
            return error.InvalidFixedPointNumber;
        }
        return ret;
    }

    pub fn toDbRepr(self: FixedPointNumber) i32 {
        return @bitCast(self);
    }

    pub fn toFloat(self: FixedPointNumber) f32 {
        var ret: f32 = @floatFromInt(self.fractional);
        std.debug.assert(self.fractional < 1000);
        ret /= 1000;
        ret += @floatFromInt(self.integer);
        return ret;
    }

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) std.json.ParseError(@TypeOf(source.*))!FixedPointNumber {
        _ = options;
        const token: std.json.Token = try source.nextAlloc(allocator, .alloc_if_needed);
        switch (token) {
            .number, .allocated_number, .string, .allocated_string => |s| {
                const decimal_pos = std.mem.indexOfScalar(u8, s, '.') orelse s.len;
                const integer = try std.fmt.parseInt(u22, s[0..decimal_pos], 10);

                const fractional_start = decimal_pos + 1;
                // Only take first 3 decimals
                const fractional_end = @min(s.len, fractional_start + 3);

                const fractional = if (fractional_start < s.len) blk: {
                    const parsed_decimal = try std.fmt.parseInt(u10, s[fractional_start..fractional_end], 10);
                    // end - start == 3 -> * 1, 10^0
                    // end - start == 2 -> * 10, 10^1
                    // end - start == 1 -> * 100, 10^2
                    const multiplier = try std.math.powi(u10, 10, @intCast(3 - (fractional_end - fractional_start)));
                    break :blk parsed_decimal * multiplier;
                } else 0;

                return .{
                    .integer = integer,
                    .fractional = fractional,
                };
            },
            else => return error.UnexpectedToken,
        }
    }

    pub fn jsonStringify(self: FixedPointNumber, writer: anytype) !void {
        try writer.print("{d}.{d:03}", .{ self.integer, self.fractional });
    }
};

pub const AddIngredient = struct {
    name: []const u8,

    pub fn validate(self: AddIngredient) !void {
        if (self.name.len == 0) {
            return error.InvalidName;
        }
    }
};

pub const AddModifyProperty = struct {
    name: []const u8,

    pub fn validate(self: AddModifyProperty) !void {
        if (self.name.len == 0) return error.InvalidName;
    }
};

pub const AddIngredientPropertyParams = struct {
    ingredient_id: i64,
    property_id: i64,
};

pub const ModifyIngredientPropertyParams = struct {
    value: FixedPointNumber,

    pub fn validate(self: ModifyIngredientPropertyParams) !void {
        if (self.value.toFloat() < 0) return error.InvalidValue;
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

pub const CopyMealDishParams = struct {
    from_meal_dish_id: i64,
    to_meal_dish_id: i64,
};

pub const Target = union(enum) {
    add_ingredient,
    get_ingredients,
    get_ingredient: i64,
    get_properties,
    add_property,
    modify_property: i64,
    modify_ingredient: i64,
    add_ingredient_property,
    modify_ingredient_property: i64,
    add_dish,
    get_dishes,
    redirect_to_index,
    add_meal,
    get_meals,
    get_meal: i64,
    delete_meal: i64,
    add_meal_dish,
    add_meal_dish_ingredient,
    delete_meal_dish_ingredient: i64,
    modify_meal_dish_ingredient: i64,
    copy_meal_dish,
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
            copy_meal_dish,
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
                        .copy_meal_dish => return .copy_meal_dish,
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
                    .properties => return .{ .modify_property = id },
                    .ingredients => return .{ .modify_ingredient = id },
                    .ingredient_properties => return .{ .modify_ingredient_property = id },
                    .meal_dish_ingredients => return .{ .modify_meal_dish_ingredient = id },
                    else => return error.UnhandledMethod,
                }
            },
            .DELETE => {
                switch (api) {
                    .meals => return .{ .delete_meal = id },
                    .meal_dish_ingredients => return .{ .delete_meal_dish_ingredient = id },
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
