import * as header from "./header.js";
import {
  makeIngredients,
  makeDishes,
  makeProperties,
  Meal,
  makeMeals,
} from "./data.js";
const url = new URL(window.location.href);

const meal = new Meal(url.searchParams.get("id"));
const other_meals = makeMeals();
const ingredients = makeIngredients();
const dishes = makeDishes();
const properties = makeProperties();

/** @type HTMLSpanElement */
const meal_id_node = document.getElementById("meal_id");

/** @type HTMLButtonElement*/
const delete_meal_button = document.getElementById("delete_meal");

/** @type HTMLSelectElement */
const instantiate_dish_dropdown = document.getElementById(
  "instantiate_dish_dropdown",
);

/** @type HTMLDivElement */
const meal_dishes_node = document.getElementById("meal_dishes");

/** @type HTMLTableElement */
const summary_node = document.getElementById("summary");

const meal_dish_nodes = new Map();

const unit_mappings = [
  {
    key: "serving_size_g",
    display: "g",
    api: "mass",
  },
  {
    key: "serving_size_ml",
    display: "ml",
    api: "volume",
  },
  {
    key: "serving_size_pieces",
    display: "pieces",
    api: "pieces",
  },
];

function ingredientUnitUsable(ingredient, unit) {
  return ingredient[unit] !== undefined && ingredient[unit] !== 0;
}

function usableIngredientUnits(ingredient) {
  var ret = [];
  for (const unit_mapping of unit_mappings) {
    if (ingredientUnitUsable(ingredient, unit_mapping.key)) {
      ret.push(unit_mapping);
    }
  }
  return ret;
}

function unitDisplayToApi(display) {
  for (const unit_mapping of unit_mappings) {
    if (unit_mapping.display == display) {
      return unit_mapping.api;
    }
  }

  return null;
}

function makeTriggerOnSelectDropdown(
  select_node,
  preview_text,
  options,
  callback,
) {
  const fragment = document.createDocumentFragment();

  const preview_node = document.createElement("option");
  preview_node.innerText = preview_text;
  fragment.append(preview_node);

  for (const option_text of options) {
    const option = document.createElement("option");
    option.innerText = option_text;
    fragment.append(option);
  }

  select_node.innerHTML = "";
  select_node.append(fragment);

  select_node.onchange = (ev) => {
    // -1 because 0 is preview node
    callback(ev.target.selectedIndex - 1);
    ev.target.selectedIndex = 0;
  };
}

function populateMealDishIngredientUnits(
  unit_select,
  meal_dish_ingredient,
  ingredient,
) {
  const usable_units = usableIngredientUnits(ingredient);

  if (usable_units.length == 0) {
    const option = document.createElement("option");
    option.innerText = "No valid units";
    unit_select.append(option);
  }

  for (let i = 0; i < usable_units.length; i++) {
    const unit = usable_units[i];
    const option = document.createElement("option");
    option.innerText = unit.display;
    unit_select.append(option);

    if (unit.api === meal_dish_ingredient.unit) {
      unit_select.selectedIndex = i;
    }
  }
}

function appendMealDishIngredient(parent_div, meal_dish, meal_dish_ingredient) {
  const ingredient = ingredients.getById(meal_dish_ingredient.ingredient_id);

  const fragment = document.createDocumentFragment();

  const first_grid_div = document.createElement("div");
  fragment.append(first_grid_div);

  const checkbox = document.createElement("input");
  checkbox.type = "checkbox";
  first_grid_div.append(checkbox);

  const label = document.createElement("a");
  label.innerText = ingredient.name;
  label.href = "/ingredient.html?id=" + ingredient.id;
  first_grid_div.append(label);

  const input = document.createElement("input");
  input.type = "number";
  input.value = meal_dish_ingredient.quantity;
  fragment.append(input);

  const unit_select = document.createElement("select");
  populateMealDishIngredientUnits(
    unit_select,
    meal_dish_ingredient,
    ingredient,
  );
  fragment.append(unit_select);

  const delete_button = document.createElement("button");
  fragment.append(delete_button);

  delete_button.innerText = "Delete";
  delete_button.onclick = async () => {
    await meal_dish.removeIngredient(meal_dish_ingredient.id);

    parent_div.removeChild(first_grid_div);
    parent_div.removeChild(input);
    parent_div.removeChild(unit_select);
    parent_div.removeChild(delete_button);

    if (meal_dish.ingredients().length === 0) {
      markIngredientNodeFresh(meal_dish_nodes.get(meal_dish.id()));
    }
  };

  input.onchange = () =>
    updateMealDishIngredient(
      meal_dish_ingredient.id,
      input.value,
      unitDisplayToApi(unit_select.value),
    );

  unit_select.onchange = () =>
    updateMealDishIngredient(
      meal_dish_ingredient.id,
      input.value,
      unitDisplayToApi(unit_select.value),
    );
  parent_div.append(fragment);
}

async function updateMealDishIngredient(id, quantity, unit) {
  await fetch("/meal_dish_ingredients/" + id, {
    method: "PUT",
    body: JSON.stringify({
      quantity: quantity,
      unit: unit,
    }),
  });

  await meal.update();
  updateSummary();
}

function updateSummary() {
  const fragment = document.createDocumentFragment();
  for (const entry of meal.data.summary) {
    const row = document.createElement("tr");
    fragment.append(row);

    const name_col = document.createElement("td");
    row.append(name_col);

    const value_col = document.createElement("td");
    row.append(value_col);

    name_col.innerText = properties.getById(entry.property_id).name;
    value_col.innerText = entry.value;
  }

  summary_node.replaceChildren(fragment);
}

function makeAddIngredientDropdown(meal_dish) {
  const select = document.createElement("select");

  const ingredient_names = ingredients.items.map((elem) => elem.name);
  makeTriggerOnSelectDropdown(
    select,
    "Add an ingredient...",
    ingredient_names,
    (idx) => {
      meal_dish.addIngredient(ingredients.items[idx].id);
    },
  );

  return select;
}

function getOtherMealsForDish(dish_id) {
  const ret = [];

  for (let previous_meal of other_meals.items) {
    if (previous_meal.id == meal.id) {
      continue;
    }

    const dishes = previous_meal.dishes;

    for (let meal_dish of dishes) {
      if (meal_dish.dish_id == dish_id) {
        ret.push([previous_meal.id, meal_dish.id]);
        break;
      }
    }
  }

  return ret;
}

function makeOtherVersionsNode(meal_dish) {
  const dish_id = meal_dish.dish_id();

  const elem = document.createElement("table");
  const previous_meals = getOtherMealsForDish(dish_id);
  for (let [previous_meal_id, previous_meal_dish_id] of previous_meals) {
    const row = document.createElement("tr");

    const link_col = document.createElement("td");
    row.append(link_col);

    const link = document.createElement("a");
    link_col.append(link);

    link.href = "/meal.html?id=" + previous_meal_id;
    const previous_meal = other_meals.getById(previous_meal_id);
    const previous_date = new Date(previous_meal.timestamp_utc);
    link.innerText = previous_date.toLocaleDateString();

    const copy_col = document.createElement("td");
    copy_col.classList.add("copy_dish");
    row.append(copy_col);

    const copy_button = document.createElement("button");
    copy_col.append(copy_button);

    copy_button.innerText = "Copy";
    copy_button.onclick = async () => {
      meal_dish.copyFrom(previous_meal_dish_id);
    };

    elem.append(row);
  }
  return elem;
}

function markIngredientNodeModified(node) {
  if (node !== undefined) {
    node.classList.add("ingredients_added");
  }
}

function markIngredientNodeFresh(node) {
  if (node !== undefined) {
    node.classList.remove("ingredients_added");
  }
}

function appendMealDish(meal_dish) {
  const meal_dish_id = meal_dish.id();
  const div = document.createElement("div");

  const name = document.createElement("h2");
  const dish_name = dishes.getById(meal_dish.dish_id()).name;
  name.innerText = dish_name;
  div.append(name);

  const meal_content = document.createElement("div");
  meal_content.classList.add("meal-content");
  div.append(meal_content);

  const ingredient_div = document.createElement("div");
  ingredient_div.classList.add("ingredients_table");
  meal_content.append(ingredient_div);

  const dish_buttons_div = document.createElement("div");
  dish_buttons_div.classList.add("dish_buttons");
  meal_content.append(dish_buttons_div);

  dish_buttons_div.append(makeAddIngredientDropdown(meal_dish));

  const delete_dish = document.createElement("button");
  delete_dish.innerText = "Delete " + dish_name;
  delete_dish.onclick = async () => {
    await meal.deleteDish(meal_dish_id);
    meal_dish_nodes.delete(meal_dish_id);
    div.remove();
    updateSummary();
  };

  dish_buttons_div.append(delete_dish);

  meal_dish.setIngredientCallback((mdi) => {
    appendMealDishIngredient(ingredient_div, meal_dish, mdi);
    console.log(meal_dish_id);
    markIngredientNodeModified(meal_dish_nodes.get(meal_dish_id));
  });

  meal_dish.remove_ingredient_callback = (id) => {
    console.log(`Removed id: ${id}`);
  };

  const previous_versions_header = document.createElement("h3");
  previous_versions_header.innerText = "Other versions...";
  meal_content.append(previous_versions_header);
  meal_content.append(makeOtherVersionsNode(meal_dish));

  console.log(meal_dish.ingredients());
  if (meal_dish.ingredients().length > 0) {
    markIngredientNodeModified(div);
  }

  meal_dish_nodes.set(meal_dish_id, div);

  meal_dishes_node.append(div);
}

async function init() {
  header.prependHeaderToBody();
  const id = parseInt(url.searchParams.get("id"));

  meal.on_new_dish = appendMealDish;

  await Promise.all([
    ingredients.initFromServer(),
    dishes.initFromServer(),
    properties.initFromServer(),
    other_meals.initFromServer(),
  ]);

  // FIXME: APIs should allow the network stuff to be separated from UI stuff
  await meal.initFromServer();

  meal_id_node.innerText = `${id} (${meal.date().toLocaleDateString()})`;

  updateSummary();

  const dish_names = dishes.items.map((elem) => elem.name);
  makeTriggerOnSelectDropdown(
    instantiate_dish_dropdown,
    "Add a dish...",
    dish_names,
    (idx) => {
      const dish = dishes.items[idx];
      meal.addDish({
        meal_id: id,
        dish_id: dish.id,
      });
    },
  );

  delete_meal_button.onclick = async () => {
    try {
      await meal.deleteMeal();
      window.location.href = "/meals.html";
    } catch {
      // Put error somewhere visible to user
    }
  };
}

window.onload = init;
