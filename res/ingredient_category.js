import * as header from "./header.js";
import { IngredientCategory, makeIngredients } from "./data.js";
import "./sphdelete-button.js";

const url = new URL(window.location.href);
const category_id = url.searchParams.get("id");
const ingredient_category = new IngredientCategory(category_id);
const ingredients = makeIngredients();

/** @type HTMLInputElement */
const title = document.getElementById("category_name_edit");
/** @type HTMLDivElement */
const ingredient_links = document.getElementById("ingredient_links");
/** @type Sphearch */
const add_ingredient_node = document.getElementById("add_ingredient_search");

function appendLink(mapping, node) {
  const delete_button = document.createElement("sphdelete-button");
  node.append(delete_button);

  const link = document.createElement("a");
  const ingredient = ingredients.getById(mapping.ingredient_id);
  link.innerText = ingredient.name;
  link.href = `/ingredient.html?id=${mapping.ingredient_id}`;
  link.style.display = "block";
  if (ingredient.fully_entered !== true) {
    link.classList.add("incomplete_link");
  }
  node.append(link);

  const mapping_id = mapping.id;
  delete_button.onclick = async () => {
    await ingredient_category.deleteMapping(mapping_id);

    ingredient_links.removeChild(link);
    ingredient_links.removeChild(delete_button);
  };
}

async function init() {
  header.prependHeaderToBody();

  await Promise.all([
    ingredient_category.initFromServer(),
    ingredients.initFromServer(),
  ]);

  title.value = ingredient_category.data.name;
  title.onchange = (ev) => {
    ingredient_category.modify({
      name: ev.target.value,
    });
  };

  let searched_ingredients = ingredients.items;
  add_ingredient_node.search_results = (search_string) => {
    searched_ingredients = ingredients.items.filter((item) =>
      item.name.includes(search_string),
    );
    return searched_ingredients.map((item) => item.name);
  };

  add_ingredient_node.on_select = (idx) => {
    ingredient_category.addIngredient(searched_ingredients[idx].id);
  };

  add_ingredient_node.setSearchResults(
    ingredients.items.map((item) => item.name),
  );

  const fragment = document.createDocumentFragment();
  for (const mapping of ingredient_category.data.mappings) {
    appendLink(mapping, fragment);
  }

  ingredient_category.on_new_ingredient = (mapping) =>
    appendLink(mapping, ingredient_links);

  ingredient_links.append(fragment);
}

window.onload = init;
