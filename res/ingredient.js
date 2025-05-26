import * as header from "./header.js";
const url = new URL(window.location.href);

async function modifyIngredient(id, params, properties) {
  const response = await fetch("/ingredients/" + id, {
    method: "PUT",
    body: JSON.stringify(params),
  });
  const ingredient = await response.json();

  updatePageWithIngredient(ingredient, properties);
}

/** @type HTMLHeadingElement */
const title = document.getElementById("ingredient_name");
/** @type HTMLInputElement */
const serving_size_g = document.getElementById("serving_size_g");
/** @type HTMLInputElement */
const serving_size_ml = document.getElementById("serving_size_ml");
/** @type HTMLInputElement */
const serving_size_pieces = document.getElementById("serving_size_pieces");
/** @type HTMLSelectElement */
const new_property = document.getElementById("new_property");
/** @type HTMLDivElement */
const ingredient_properties = document.getElementById("ingredient_properties");

function updatePageWithProperties(properties) {
  new_property.innerHTML = "";

  const preview_option = document.createElement("option");
  preview_option.selected = true;
  preview_option.disabled = true;
  preview_option.hidden = true;
  preview_option.innerText = "Add a property...";

  new_property.append(preview_option);
  for (const property of properties) {
    const option = document.createElement("option");
    option.innerText = property.name;
    new_property.append(option);
  }
}

function getProperty(properties, id) {
  for (const property of properties) {
    if (id == property.id) {
      return property;
    }
  }

  return null;
}

function updatePageWithIngredient(ingredient, properties) {
  title.innerText = ingredient.name;
  serving_size_g.value = ingredient.serving_size_g;
  serving_size_ml.value = ingredient.serving_size_ml;
  serving_size_pieces.value = ingredient.serving_size_pieces;

  // FIXME: createDoucumentFragment?

  ingredient_properties.innerHTML = "";

  for (const ingredient_property of ingredient.properties) {
    const key_value_div = document.createElement("div");

    const label = document.createElement("label");
    const property = getProperty(properties, ingredient_property.property_id);
    label.innerText = property.name;
    key_value_div.append(label);

    const input = document.createElement("input");
    input.type = "number";
    input.min = 0;
    input.value = ingredient_property.value;
    const id = ingredient_property.id;
    input.onchange = (ev) => {
      fetch("/ingredient_properties/" + id, {
        method: "PUT",
        body: JSON.stringify({
          value: ev.target.value,
        }),
      });
    };
    key_value_div.append(input);

    ingredient_properties.append(key_value_div);
  }
}

async function addProperty(id, properties, selected_property) {
  const property = properties[selected_property - 1];
  console.log(property.id);

  await fetch("/ingredient_properties", {
    method: "PUT",
    body: JSON.stringify({
      ingredient_id: id,
      property_id: property.id,
    }),
  });

  const response = await fetch("/ingredients/" + id);
  const ingredient = await response.json();
  updatePageWithIngredient(ingredient, properties);
}

async function init() {
  header.prependHeaderToBody();
  const id = url.searchParams.get("id");
  const ingredient_promise = fetch("/ingredients/" + id).then((response) =>
    response.json(),
  );
  const properties_promise = fetch("/properties").then((response) =>
    response.json(),
  );

  const [ingredient, properties] = await Promise.all([
    ingredient_promise,
    properties_promise,
  ]);

  console.log(properties);
  updatePageWithProperties(properties);
  updatePageWithIngredient(ingredient, properties);

  serving_size_g.oninput = (ev) =>
    modifyIngredient(
      id,
      {
        serving_size_g: ev.target.value,
      },
      properties,
    );

  serving_size_ml.oninput = (ev) =>
    modifyIngredient(
      id,
      {
        serving_size_ml: ev.target.value,
      },
      properties,
    );

  serving_size_pieces.oninput = (ev) =>
    modifyIngredient(
      id,
      {
        serving_size_pieces: ev.target.value,
      },
      properties,
    );

  new_property.onchange = (ev) => {
    addProperty(id, properties, ev.target.selectedIndex);
    // Force it back to preview
    new_property.selectedIndex = 0;
  };
}

window.onload = init;
