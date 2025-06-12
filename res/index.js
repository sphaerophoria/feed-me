import * as header from "./header.js";
import { makeIngredients } from "./data.js";

let ingredients = makeIngredients();

const ingredient_list = document.getElementById("ingredient_list");

async function appendToIngredientList(ingredient) {
  const link = document.createElement("a");
  link.href = "/ingredient.html?id=" + ingredient.id;
  link.innerText = ingredient.name;
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

  await ingredients.initFromServer();

  ingredients.items.sort((a, b) => {
    if (a.name < b.name) {
      return -1;
    }
    if (a.name > b.name) {
      return 1;
    }
    return 0;
  });

  for (let ingredient of ingredients.items) {
    appendToIngredientList(ingredient);
  }

  ingredients.new_callback = appendToIngredientList;
}

window.onload = init;
