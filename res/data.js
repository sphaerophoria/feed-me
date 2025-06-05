class RemoteItemArray {
  constructor(url) {
    this.url = url;
    this.items = [];
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
    this.items = await response.json();
  }

  async add(params) {
    const response = await fetch(this.url, {
      method: "PUT",
      body: params !== null ? JSON.stringify(params) : null,
    });
    const json = await response.json();
    this.items.push(json);
    if (this.new_callback !== null) {
      this.new_callback(json);
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
  return new RemoteItemArray("/properties");
}

function makeDishes() {
  return new RemoteItemArray("/dishes");
}

function makeMeals() {
  return new RemoteItemArray("/meals");
}

export { makeIngredients, makeProperties, makeDishes, makeMeals, Meal };
