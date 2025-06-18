import * as header from "./header.js";
import { makeIngredients, makeIngredientCategories } from "./data.js";

let ingredients = makeIngredients();
let ingredient_categories = makeIngredientCategories();

const ingredient_list = document.getElementById("ingredient_list");

async function appendToIngredientList(name, url, complete) {
  const link = document.createElement("a");
  if (complete !== true) {
    link.classList.add("incomplete_link");
  }
  link.href = url;
  link.innerText = name;
  ingredient_list.append(link);
  ingredient_list.append(document.createElement("br"));
}

async function addIngredient() {
  ingredients.add({
    name: ingredient_name.value,
  });
  ingredient_name.value = "";
}

async function init() {
  header.prependHeaderToBody();

  add_button.onclick = addIngredient;

  ingredient_name.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addIngredient();
    }
  };

  await Promise.all([
    ingredients.initFromServer(),
    ingredient_categories.initFromServer(),
  ]);

  const url_list = [];
  for (const ingredient of ingredients.items) {
    if (ingredient.category_mappings.length === 0) {
      url_list.push([
        ingredient.name,
        `/ingredient.html?id=${ingredient.id}`,
        ingredient.fully_entered,
      ]);
    }
  }

  for (const category of ingredient_categories.items) {
    url_list.push([
      category.name,
      `/ingredient_category.html?id=${category.id}`,
      category.fully_entered,
    ]);
  }

  url_list.sort((a, b) => {
    if (a[0] < b[0]) {
      return -1;
    }
    if (a[0] > b[0]) {
      return 1;
    }
    return 0;
  });

  for (const [name, url, fully_entered] of url_list) {
    appendToIngredientList(name, url, fully_entered);
  }

  ingredients.new_callback = (ingredient) =>
    appendToIngredientList(
      ingredient.name,
      `/ingredient.html?id=${ingredient.id}`,
      ingredient.fully_entered,
    );
}

window.onload = init;
