import * as header from "./header.js";
import { Ingredient, makeProperties } from "./data.js";
const url = new URL(window.location.href);
import "./sphdelete-button.js";

const ingredient_id = url.searchParams.get("id");
const ingredient = new Ingredient(ingredient_id);
const properties = makeProperties();

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

  input.onfocus = (ev) => {
    ev.target.select();
  };

  key_value_div.append(input);

  ingredient_properties_node.append(key_value_div);

  if (focus === true) {
    input.focus();
  }
}

async function init() {
  header.prependHeaderToBody();

  await Promise.all([ingredient.initFromServer(), properties.initFromServer()]);

  for (const ingredient_property of ingredient.data.properties) {
    appendPropertyToList(ingredient_property, false);
  }

  ingredient.on_new_property = (prop) => appendPropertyToList(prop, true);

  updatePageWithProperties();
  updatePageWithIngredient();

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
}

window.onload = init;
