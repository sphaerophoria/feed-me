class RemoteItemArray {
  constructor(url, ItemType) {
    this.url = url;
    this.items = [];
    this.ItemType = ItemType;
    this.new_callback = null;
  }

  async initFromServer() {
    await this.update();
    if (this.new_callback !== null) {
      for (const item of this.items) {
        this.new_callback(item);
      }
    }
  }

  async update() {
    // FIXME: This should check for new items vs existing ones and call
    // new_callback but for now this is good enough :)
    const response = await fetch(this.url);
    const json = await response.json();
    if (this.ItemType !== undefined) {
      this.items = json.map((item) => new this.ItemType(item));
    } else {
      this.items = json;
    }
  }

  async add(params) {
    const response = await fetch(this.url, {
      method: "PUT",
      body: params !== null ? JSON.stringify(params) : null,
    });

    if (response.status != 200) {
      throw new Error("Failed to add property");
    }

    const json = await response.json();
    const item = this.ItemType !== undefined ? new this.ItemType(json) : json;
    this.items.push(item);
    if (this.new_callback !== null) {
      this.new_callback(item);
    }

    return json;
  }

  getById(id) {
    for (const elem of this.items) {
      if (elem.id == id) return elem;
    }

    return null;
  }
}

class Property {
  constructor(data) {
    this.data = data;
  }

  get id() {
    return this.data.id;
  }

  get name() {
    return this.data.name;
  }

  get parent_id() {
    return this.data.parent_id;
  }

  modify(new_name) {
    fetch("/properties/" + this.id, {
      method: "PUT",
      body: JSON.stringify({
        name: new_name,
      }),
    });
  }
}

class Dish {
  constructor(data) {
    this.data = data;
  }

  get id() {
    return this.data.id;
  }

  get name() {
    return this.data.name;
  }

  modify(new_name) {
    fetch("/dishes/" + this.id, {
      method: "PUT",
      body: JSON.stringify({
        name: new_name,
      }),
    });
  }
}

class MealDish {
  constructor(data) {
    this.new_ingredient_callback = null;
    this.data = data;
  }

  id() {
    return this.data.id;
  }

  dish_id() {
    return this.data.dish_id;
  }

  ingredients() {
    return this.data.ingredients;
  }

  setIngredientCallback(callback) {
    for (const ingredient of this.ingredients()) {
      callback(ingredient);
    }

    this.new_ingredient_callback = callback;
  }

  async addIngredient(ingredient_id) {
    const response = await fetch("/meal_dish_ingredients", {
      method: "PUT",
      body: JSON.stringify({
        meal_dish_id: this.id(),
        ingredient_id: ingredient_id,
      }),
    });

    const new_ingredient = await response.json();
    this.data.ingredients.push(new_ingredient);
    if (this.new_ingredient_callback !== null) {
      this.new_ingredient_callback(new_ingredient);
    }
    return new_ingredient;
  }

  async removeIngredient(id) {
    const response = await fetch("/meal_dish_ingredients/" + id, {
      method: "DELETE",
    });

    if (response.status != 200) {
      throw new Error("Failed to delete meal dish ingredient");
    }

    for (let i = 0; i < this.data.ingredients.length; i++) {
      if (this.data.ingredients[i].id === id) {
        this.data.ingredients.splice(i, 1);
      }
    }
  }

  async copyFrom(id) {
    const response = await fetch("/copy_meal_dish", {
      method: "PUT",
      body: JSON.stringify({
        from_meal_dish_id: id,
        to_meal_dish_id: this.id(),
      }),
    });

    if (response.status != 200) {
      throw new Error("Failed to copy meal dish ingredient");
    }

    const ingredients = await response.json();
    for (const ingredient of ingredients) {
      this.data.ingredients.push(ingredient);
      if (this.new_ingredient_callback !== null) {
        this.new_ingredient_callback(ingredient);
      }
    }
  }
}

class Meal {
  constructor(id) {
    this.id = id;
    this.data = {};
    this.on_new_dish = null;
  }

  async initFromServer() {
    await this.update();
    if (this.on_new_dish !== null) {
      for (const dish of this.data.dishes) {
        this.on_new_dish(dish);
      }
    }
  }

  async update() {
    const response = await fetch(this.mealUrl());
    this.data = await response.json();
    this.data.dishes = this.data.dishes.map((data) => new MealDish(data));
  }

  mealUrl() {
    return "/meals/" + this.id;
  }

  date() {
    return new Date(this.data.timestamp_utc);
  }

  async deleteMeal() {
    const response = await fetch(this.mealUrl(), {
      method: "DELETE",
    });
    if (response.status != 200) {
      throw new Error("Failed to delete moeal");
    }
  }

  async addDish(params) {
    const response = await fetch("/meal_dishes", {
      method: "PUT",
      body: JSON.stringify(params),
    });
    const new_dish = new MealDish(await response.json());
    this.data.dishes.push(new_dish);
    if (this.on_new_dish) {
      this.on_new_dish(new_dish);
    }
  }

  async deleteDish(meal_dish_id) {
    const response = await fetch("/meal_dishes/" + meal_dish_id, {
      method: "DELETE",
    });

    if (response.status != 200) {
      throw new Error("Failed to remove dish");
    }

    for (let i = 0; i < this.data.dishes.length; i++) {
      if (this.data.dishes[i].id() === meal_dish_id) {
        this.data.dishes.splice(i, 1);
        break;
      }
    }
  }
}

class Ingredient {
  constructor(id) {
    this.id = id;
    this.data = {};
    this.on_new_property = null;
  }

  async initFromServer() {
    const response = await fetch("/ingredients/" + this.id);

    if (response.status != 200) {
      throw new Error("Failed to get ingredient");
    }

    this.data = await response.json();
    if (this.on_new_property !== null) {
      for (const ingredient_property of this.data.properties) {
        this.on_new_property(ingredient_property);
      }
    }
  }

  async addProperty(property_id) {
    const response = await fetch("/ingredient_properties", {
      method: "PUT",
      body: JSON.stringify({
        ingredient_id: this.id,
        property_id: property_id,
      }),
    });

    if (response.status != 200) {
      throw new Error("Failed to add ingredient property");
    }

    const new_property = await response.json();
    this.data.properties.push(new_property);

    if (this.on_new_property !== null) {
      this.on_new_property(new_property);
    }
  }

  async modifyIngredient(params) {
    const response = await fetch("/ingredients/" + this.id, {
      method: "PUT",
      body: JSON.stringify(params),
    });

    if (response.status != 200) {
      throw new Error("Failed to modify ingredient");
    }

    this.data = await response.json();
  }

  async deleteProperty(ingredient_property_id) {
    const response = await fetch(
      "/ingredient_properties/" + ingredient_property_id,
      {
        method: "DELETE",
      },
    );

    if (response.status != 200) {
      throw new Error("Failed to delete property");
    }

    for (let i = 0; i < this.data.properties.length; i++) {
      if (this.data.properties[i].id === ingredient_property_id) {
        this.data.properties.splice(i, 1);
        break;
      }
    }
  }
}

class IngredientCategory {
  constructor(id) {
    this.id = id;
    this.data = {};
    this.on_new_ingredient = null;
  }

  async initFromServer() {
    const response = await fetch(this.makeUrl());

    if (response.status != 200) {
      throw new Error("Failed to get ingredient category");
    }

    this.data = await response.json();
  }

  async modify(params) {
    const response = await fetch(this.makeUrl(), {
      method: "PUT",
      body: JSON.stringify(params),
    });

    if (response.status != 200) {
      throw new Error("Failed to update ingredient category");
    }

    for (const [key, value] in params) {
      this.data[key] = value;
    }
  }

  async addIngredient(ingredient_id) {
    const response = await fetch("/ingredient_category_mappings", {
      method: "PUT",
      body: JSON.stringify({
        category_id: this.id,
        ingredient_id: ingredient_id,
      }),
    });

    if (response.status != 200) {
      throw new Error("Failed to add ingredient to category");
    }

    const json = await response.json();
    this.data.mappings.push(json);
    if (this.on_new_ingredient) {
      this.on_new_ingredient(json);
    }
  }

  async deleteMapping(mapping_id) {
    const response = await fetch(
      "/ingredient_category_mappings/" + mapping_id,
      {
        method: "DELETE",
      },
    );

    if (response.status != 200) {
      throw new Error("Failed to remove ingredient from category");
    }

    for (let i = 0; i < this.data.mappings.length; i++) {
      if (this.data.mappings[i].id === mapping_id) {
        this.data.mappings.splice(i, 1);
        break;
      }
    }
  }

  makeUrl() {
    return "/ingredient_categories/" + this.id;
  }
}

function makeIngredients() {
  return new RemoteItemArray("/ingredients");
}

function makeProperties() {
  return new RemoteItemArray("/properties", Property);
}

function makeDishes() {
  return new RemoteItemArray("/dishes", Dish);
}

function makeMeals() {
  return new RemoteItemArray("/meals");
}

function makeIngredientCategories() {
  return new RemoteItemArray("/ingredient_categories");
}

export {
  makeIngredients,
  makeProperties,
  makeDishes,
  makeMeals,
  makeIngredientCategories,
  Meal,
  Ingredient,
  IngredientCategory,
};
