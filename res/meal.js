import * as header from "./header.js";
import { makeIngredients, makeDishes, makeProperties, Meal } from "./data.js";
const url = new URL(window.location.href);

const meal = new Meal(url.searchParams.get("id"));
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

function appendMealDishIngredient(table, meal_dish_ingredient) {
  const ingredient = ingredients.getById(meal_dish_ingredient.ingredient_id);
  const new_row = document.createElement("tr");

  const label_col = document.createElement("td");
  new_row.append(label_col);

  const input_col = document.createElement("td");
  new_row.append(input_col);

  const unit_col = document.createElement("td");
  new_row.append(unit_col);

  const label = document.createElement("a");
  label.innerText = ingredient.name;
  label.href = "/ingredient.html?id=" + ingredient.id;
  label_col.append(label);

  const input = document.createElement("input");
  input.type = "number";
  input.value = meal_dish_ingredient.quantity;
  input_col.append(input);

  const unit_select = document.createElement("select");
  populateMealDishIngredientUnits(
    unit_select,
    meal_dish_ingredient,
    ingredient,
  );
  unit_col.append(unit_select);

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

  table.append(new_row);
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

function appendMealDish(meal_dish) {
  const div = document.createElement("div");

  const name = document.createElement("h2");
  name.innerText = dishes.getById(meal_dish.dish_id()).name;
  div.append(name);

  const meal_content = document.createElement("div");
  meal_content.classList.add("meal-content");
  div.append(meal_content);

  const ingredient_table = document.createElement("table");
  meal_content.append(ingredient_table);
  meal_content.append(makeAddIngredientDropdown(meal_dish));

  meal_dish.setIngredientCallback((mdi) =>
    appendMealDishIngredient(ingredient_table, mdi),
  );

  meal_dishes_node.append(div);
}

async function init() {
  header.prependHeaderToBody();
  const id = parseInt(url.searchParams.get("id"));
  meal_id_node.innerText = id;

  meal.on_new_dish = appendMealDish;

  await Promise.all([
    ingredients.initFromServer(),
    dishes.initFromServer(),
    properties.initFromServer(),
  ]);

  // FIXME: APIs should allow the network stuff to be separated from UI stuff
  await meal.initFromServer();

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
