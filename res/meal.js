import * as header from "./header.js";
import * as property_helpers from "./property_helpers.js";
import {
  makeIngredients,
  makeDishes,
  makeProperties,
  Meal,
  makeMeals,
} from "./data.js";
const url = new URL(window.location.href);
import "./sphdelete-button.js";

const meal = new Meal(url.searchParams.get("id"));
const other_meals = makeMeals();
const ingredients = makeIngredients();
const dishes = makeDishes();
const properties = makeProperties();
const ingredient_links = new Map();

/** @type HTMLSpanElement */
const meal_id_node = document.getElementById("meal_id");

/** @type HTMLButtonElement*/
const delete_meal_button = document.getElementById("delete_meal");

/** @type Sphearch */
const instantiate_dish_search = document.getElementById("instantiate_dish");

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
  label.classList.toggle("incomplete_link", ingredient.fully_entered !== true);

  if (!ingredient_links.has(ingredient.id)) {
    ingredient_links.set(ingredient.id, []);
  }
  const this_ingredient_links = ingredient_links.get(ingredient.id);
  this_ingredient_links.push(label);

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
  property_helpers.updateSummaryNode(
    summary_node,
    meal.data.summary,
    meal.data.summary_complete,
    properties,
  );
}

function makeAddIngredientDropdown(meal_dish) {
  /** @type Sphearch */
  const search = document.createElement("sphearch-bar");
  search.setAttribute("autoselect", true);
  search.setAttribute("placeholder", "Add an ingredient...");

  let results = ingredients.items;
  search.setSearchResults(results.map((elem) => elem.name));
  search.search_results = (text) => {
    results = ingredients.items.filter((ingredient) =>
      ingredient.name.toLowerCase().includes(text),
    );
    return results.map((elem) => elem.name);
  };

  search.on_select = async (idx) => {
    await meal_dish.addIngredient(results[idx].id);
    search.search_box.value = "";
    results = ingredients.items;
    search.setSearchResults(results.map((elem) => elem.name));
  };

  return search;
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

  const header_bar = document.createElement("div");
  header_bar.classList.add("dish_header");
  div.append(header_bar);

  const delete_button = document.createElement("sphdelete-button");
  header_bar.append(delete_button);

  delete_button.onclick = async () => {
    await meal.deleteDish(meal_dish_id);
    meal_dish_nodes.delete(meal_dish_id);
    div.remove();
    updateSummary();
  };

  const name = document.createElement("h2");
  const dish_name = dishes.getById(meal_dish.dish_id()).name;
  name.innerText = dish_name;
  header_bar.append(name);

  const meal_content = document.createElement("div");
  meal_content.classList.add("meal-content");
  div.append(meal_content);

  const ingredient_div = document.createElement("div");
  ingredient_div.classList.add("ingredients_table");
  ingredient_div.classList.add("common_grid");
  meal_content.append(ingredient_div);

  meal_content.append(makeAddIngredientDropdown(meal_dish));

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

function updateMealDishHighlights() {
  for (const [id, elems] of ingredient_links) {
    const ingredient = ingredients.getById(id);
    const incomplete = ingredient.fully_entered !== true;
    for (const elem of elems) {
      elem.classList.toggle("incomplete_link", incomplete);
    }
  }
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

  let search_dishes = dishes.items;
  instantiate_dish_search.setSearchResults(
    search_dishes.map((elem) => elem.name),
  );

  instantiate_dish_search.search_results = (text) => {
    search_dishes = dishes.items.filter((elem) =>
      elem.name.toLowerCase().includes(text),
    );
    return search_dishes.map((elem) => elem.name);
  };

  instantiate_dish_search.on_select = async (idx) => {
    const dish = search_dishes[idx];
    await meal.addDish({
      meal_id: id,
      dish_id: dish.id,
    });
    instantiate_dish_search.search_box.value = "";
    instantiate_dish_search.setSearchResults(
      dishes.items.map((elem) => elem.name),
    );
  };

  delete_meal_button.onclick = async () => {
    try {
      await meal.deleteMeal();
      window.location.href = "/meals.html";
    } catch {
      // Put error somewhere visible to user
    }
  };

  window.onpageshow = async () => {
    await Promise.all([ingredients.update(), meal.update()]);
    updateMealDishHighlights();
    updateSummary();
  };
}

window.onload = init;
