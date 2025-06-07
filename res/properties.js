import * as header from "./header.js";
import { makeProperties } from "./data.js";

const properties = makeProperties();

function appendIdxToId(node, idx) {
  node.id = node.id + "_" + idx;
}

/** @type HTMLInputElement */
const new_property_name_node = document.getElementById("new_property_name");
/** @type HTMLDivElement */
const properties_node = document.getElementById("properties");

function appendToPropertyList(property) {
  const input = document.createElement("input");
  input.value = property.name;
  properties_node.append(input);
}

async function init() {
  header.prependHeaderToBody();
  properties.new_callback = appendToPropertyList;

  document.getElementById("add_new_property").onclick = addProperty;
  new_property_name_node.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addProperty();
    }
  };

  await properties.initFromServer();
}

async function addProperty() {
  await properties.add({
    name: new_property_name_node.value,
  });
  new_property_name_node.value = "";
}

window.onload = init;
