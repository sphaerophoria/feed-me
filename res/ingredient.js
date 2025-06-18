import * as header from "./header.js";
import {
  Ingredient,
  makeProperties,
  makeIngredientCategories,
} from "./data.js";
const url = new URL(window.location.href);
import "./sphdelete-button.js";

const ingredient_id = url.searchParams.get("id");
const ingredient = new Ingredient(ingredient_id);
const properties = makeProperties();
const categories = makeIngredientCategories();

/** @type HTMLInputElement */
const title = document.getElementById("ingredient_name_edit");
/** @type HTMLInputElement */
const serving_size_g = document.getElementById("serving_size_g");
/** @type HTMLInputElement */
const serving_size_ml = document.getElementById("serving_size_ml");
/** @type HTMLInputElement */
const serving_size_pieces = document.getElementById("serving_size_pieces");
/** @type Sphearch */
const new_property = document.getElementById("new_property");
/** @type HTMLDivElement */
const ingredient_properties_node = document.getElementById(
  "ingredient_properties",
);
/** @type HTMLButtonElement */
const promote_to_category_button = document.getElementById("promote_category");
/** @type HTMLDivElement */
const category_list_node = document.getElementById("category_list");
/** @type HTMLInputElement */
const fully_entered_checkbox = document.getElementById("complete_checkbox");

function updatePageWithProperties() {
  const property_names = properties.items.map((elem) => elem.name);
  let out_properties = properties.items;

  new_property.search_results = (search) => {
    out_properties = properties.items.filter((elem) =>
      elem.name.includes(search),
    );
    return out_properties.map((elem) => elem.name);
  };

  new_property.on_select = async (idx) => {
    await ingredient.addProperty(out_properties[idx].id);
    new_property.clear();
  };

  new_property.setSearchResults(property_names);
}

function getProperty(properties, id) {
  for (const property of properties.items) {
    if (id == property.id) {
      return property;
    }
  }

  return null;
}

function updatePageWithIngredient() {
  title.value = ingredient.data.name;
  serving_size_g.value = ingredient.data.serving_size_g;
  serving_size_ml.value = ingredient.data.serving_size_ml;
  serving_size_pieces.value = ingredient.data.serving_size_pieces;

  // FIXME: createDoucumentFragment?
}

function appendPropertyToList(ingredient_property, focus) {
  const key_value_div = document.createDocumentFragment();

  const delete_button = document.createElement("sphdelete-button");
  delete_button.onclick = async () => {
    await ingredient.deleteProperty(ingredient_property_id);

    ingredient_properties_node.removeChild(label);
    ingredient_properties_node.removeChild(input);
    ingredient_properties_node.removeChild(delete_button);
  };
  key_value_div.append(delete_button);

  const label = document.createElement("label");
  label.style.lineHeight = 1.0;
  const property = getProperty(properties, ingredient_property.property_id);
  label.innerText = property.name;
  key_value_div.append(label);

  const input = document.createElement("input");
  input.type = "number";
  input.min = 0;
  input.step = "any";
  input.value = ingredient_property.value;
  const ingredient_property_id = ingredient_property.id;
  input.onchange = (ev) => {
    fetch("/ingredient_properties/" + ingredient_property_id, {
      method: "PUT",
      body: JSON.stringify({
        value: ev.target.value,
      }),
    });
  };

  input.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      new_property.search_box.focus();
    }
  };

  input.onfocus = (ev) => {
    ev.target.select();
  };

  key_value_div.append(input);

  ingredient_properties_node.append(key_value_div);

  if (focus === true) {
    input.focus();
  }
}

function appendCategoryNode(category_id) {
  const link = document.createElement("a");
  link.style.display = "block";
  link.innerText = categories.getById(category_id).name;
  link.href = `/ingredient_category.html?id=${category_id}`;
  category_list_node.append(link);
}

async function init() {
  header.prependHeaderToBody();

  await Promise.all([
    ingredient.initFromServer(),
    properties.initFromServer(),
    categories.initFromServer(),
  ]);

  for (const ingredient_property of ingredient.data.properties) {
    appendPropertyToList(ingredient_property, false);
  }

  console.log(fully_entered_checkbox);
  fully_entered_checkbox.checked = ingredient.data.fully_entered;

  ingredient.on_new_property = (prop) => appendPropertyToList(prop, true);

  updatePageWithProperties();
  updatePageWithIngredient();

  fully_entered_checkbox.onchange = (ev) => {
    ingredient.modifyIngredient({
      fully_entered: ev.target.checked,
    });
  };

  serving_size_g.oninput = (ev) =>
    ingredient.modifyIngredient({
      serving_size_g: ev.target.value,
    });

  serving_size_ml.oninput = (ev) =>
    ingredient.modifyIngredient({
      serving_size_ml: ev.target.value,
    });

  serving_size_pieces.oninput = (ev) =>
    ingredient.modifyIngredient({
      serving_size_pieces: ev.target.value,
    });

  title.oninput = (ev) => {
    ingredient.modifyIngredient({
      name: ev.target.value,
    });
  };

  new_property.oninput = (ev) => {
    ev.target.scrollIntoView();
  };

  if (ingredient.data.category_mappings.length === 0) {
    promote_to_category_button.style.display = "block";
  } else {
    category_list_node.style.display = "block";
  }

  for (const mapping of ingredient.data.category_mappings) {
    appendCategoryNode(mapping.ingredient_category_id);
  }

  promote_to_category_button.onclick = async () => {
    const response = await fetch("/ingredient_categories", {
      method: "PUT",
      body: JSON.stringify({
        ingredient_id: ingredient_id,
      }),
    });

    if (response.status != 200) {
      throw new Error("Promotion failed");
    }

    const new_category = await response.json();
    categories.items.push(new_category);
    console.log("new category");
    promote_to_category_button.style.display = "none";
    category_list_node.style.display = "block";
    appendCategoryNode(new_category.id);
  };
}

window.onload = init;
