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

export { makeIngredients, makeProperties, makeDishes, makeMeals, Meal };
