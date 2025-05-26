import * as header from "./header.js";

async function updateIngrientList() {
  const res = await fetch("/ingredients");
  const ingredients = await res.json();

  /** @type HTMLDivElement */
  const ingredient_list = document.getElementById("ingredient_list");
  ingredient_list.innerHTML = "";
  for (const elem of ingredients) {
    const link = document.createElement("a");
    link.href = "/ingredient.html?id=" + elem.id;
    link.innerText = elem.name;
    ingredient_list.append(link);

    ingredient_list.append(document.createElement("br"));
  }
}

async function addIngredient() {
  await fetch("/ingredients", {
    method: "PUT",
    body: JSON.stringify({ name: ingredient_name.value }),
  });
  ingredient_name.value = "";
  updateIngrientList();
}

async function init() {
  header.prependHeaderToBody();

  add_button.onclick = addIngredient;
  ingredient_name.onkeydown = (ev) => {
    if (ev.key === "Enter") {
      addIngredient();
    }
  };

  updateIngrientList();
}
window.onload = init;
