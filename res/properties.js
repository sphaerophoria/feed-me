import * as header from "./header.js";
import { makeProperties } from "./data.js";

const properties = makeProperties();

/** @type HTMLInputElement */
const new_property_name_node = document.getElementById("new_property_name");
/** @type HTMLDivElement */
const properties_node = document.getElementById("properties");

const id_to_children_node = new Map();

function makeNewPropertyInput(input, parent_id) {
  input.placeholder = "Add (press enter)";
  input.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addProperty(ev.target, parent_id);
    }
  };
}

function calcDepth(property) {
  var depth = 0;

  while (property.parent_id !== null && property.parent_id !== undefined) {
    property = properties.getById(property.parent_id);
    depth += 1;
  }

  return depth;
}

function createPropertyNodes(property, fragment) {
  const input = document.createElement("input");
  input.value = property.name;
  input.oninput = (ev) => {
    property.modify(ev.target.value);
  };
  fragment.append(input);

  const depth = calcDepth(property);

  const sub_div = document.createElement("div");
  sub_div.classList.add("input_2");
  fragment.append(sub_div);

  const children_div = document.createElement("div");
  sub_div.append(children_div);

  if (depth < 1) {
    const new_child_input = document.createElement("input");
    makeNewPropertyInput(new_child_input, property.id);
    sub_div.append(new_child_input);
  }

  id_to_children_node.set(property.id, children_div);
}

function appendNodeToPropertyList(node, parent_id) {
  if (parent_id === undefined || parent_id === null) {
    properties_node.append(node);
  } else {
    const parent_node = id_to_children_node.get(parent_id);
    parent_node.append(node);
  }
}

function appendPropertyToPropertyList(property) {
  const fragment = document.createDocumentFragment();
  createPropertyNodes(property, fragment);
  appendNodeToPropertyList(fragment, property.parent_id);
}

async function init() {
  header.prependHeaderToBody();

  await properties.initFromServer();

  const child_fragments = [];
  for (const property of properties.items) {
    const child_fragment = document.createDocumentFragment();
    createPropertyNodes(property, child_fragment);
    child_fragments.push(child_fragment);
  }

  for (let i = 0; i < properties.items.length; i++) {
    const property = properties.items[i];
    const fragment = child_fragments[i];
    appendNodeToPropertyList(fragment, property.parent_id);
  }

  properties.new_callback = appendPropertyToPropertyList;
  makeNewPropertyInput(new_property_name_node);
}

async function addProperty(target, parent_id) {
  await properties.add({
    parent_id: parent_id,
    name: target.value,
  });
  target.value = "";
}

window.onload = init;
