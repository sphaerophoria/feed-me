import * as header from "./header.js";
import { makeDishes } from "./data.js";

let dishes = makeDishes();

/** @type HTMLInputElement */
const dish_name_node = document.getElementById("new_dish_name");

/** @type HTMLButtonElement */
const add_dish_button = document.getElementById("add_new_dish");

/** @type HTMLDivElement */
const dishes_node = document.getElementById("dishes");

async function addDish() {
  await dishes.add({
    name: dish_name_node.value,
  });
}

function appendDish(dish) {
  const a = document.createElement("div");
  a.innerText = dish.name;
  dishes_node.append(a);
}

async function init() {
  header.prependHeaderToBody();
  dishes.new_callback = appendDish;

  add_dish_button.onclick = addDish;
  dish_name_node.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addDish();
      ev.target.value = "";
    }
  };

  await dishes.initFromServer();
}

window.onload = init;
