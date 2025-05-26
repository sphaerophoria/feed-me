import * as header from "./header.js";

function appendIdxToId(node, idx) {
  node.id = node.id + "_" + idx;
}

/** @type HTMLInputElement */
const new_property_name_node = document.getElementById("new_property_name");
/** @type HTMLTemplateElement */
const property_template = document.getElementById("property_row");
/** @type HTMLDivElement */
const properties_node = document.getElementById("properties");

async function init() {
  header.prependHeaderToBody();
  populateProperties();

  document.getElementById("add_new_property").onclick = addProperty;
  new_property_name_node.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addProperty();
    }
  };
}

async function addProperty() {
  console.log("hi");
  const new_name = new_property_name_node.value;
  new_property_name_node.value = "";
  await fetch("/properties", {
    method: "PUT",
    body: JSON.stringify({
      name: new_name,
    }),
  });
  populateProperties();
}

async function populateProperties() {
  const properties_response = await fetch("/properties");
  const properties = await properties_response.json();

  const insert_fragment = document.createDocumentFragment();
  for (let i = 0; i < properties.length; ++i) {
    const property = properties[i];

    const node = property_template.content.cloneNode(true);

    const name_node = node.querySelector("#property_name");
    appendIdxToId(name_node, i);
    name_node.value = property.name;

    insert_fragment.append(node);
  }

  properties_node.innerHTML = "";
  properties_node.append(insert_fragment);
}

window.onload = init;
