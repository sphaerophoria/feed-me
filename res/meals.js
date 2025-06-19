import * as header from "./header.js";
import { makeMeals, makeDishes, makeProperties } from "./data.js";
import * as property_helpers from "./property_helpers.js";

const meals = makeMeals();
const dishes = makeDishes();
const properties = makeProperties();

let fully_initialized = false;

/** @type HTMLDivElement */
const meals_node = document.getElementById("meals");

const date_nodes = new Map();
const summary_nodes = new Map();

function makeMealUrl(id) {
  return "/meal.html?id=" + id;
}

function getMealLabel(meal) {
  if (meal.dishes.length == 0) {
    return "No food eaten yet";
  }

  const it = meal.dishes.entries();

  const first = it.next().value[1];
  console.log(first);
  const first_dish = dishes.getById(first.dish_id);
  let meal_text = first_dish.name;

  for (const [_, meal_dish] of it) {
    const dish = dishes.getById(meal_dish.dish_id);
    meal_text = meal_text + " + " + dish.name;
  }

  return meal_text;
}

function appendMealToList(meal) {
  const link = document.createElement("a");

  link.innerText = getMealLabel(meal);
  link.href = makeMealUrl(meal.id);
  if (meal.summary_complete !== true) {
    link.classList.add("incomplete_link");
  }

  const meal_date = new Date(meal.timestamp_utc);
  const parent_node = date_nodes.get(meal_date.toLocaleDateString());

  if (parent_node === undefined) {
    return;
  }

  parent_node.append(link);
  parent_node.append(document.createElement("br"));
}

function addDateNode(date, alias) {
  const date_string = date.toLocaleDateString();
  let text = date_string;
  if (alias !== undefined) {
    text = `${alias} (${date_string})`;
  }

  const parent_node = document.createElement("div");

  const header = document.createElement("h2");
  header.innerText = text;
  parent_node.append(header);

  const meals_title = document.createElement("h3");
  meals_title.innerText = "Meals";
  parent_node.append(meals_title);

  const date_meals = document.createElement("div");
  parent_node.append(date_meals);
  date_nodes.set(date_string, date_meals);

  const summary_title = document.createElement("h3");
  summary_title.innerText = "Summary";
  parent_node.append(summary_title);

  const summary_node = document.createElement("div");
  summary_node.classList.add("summary");
  summary_node.classList.add("common_grid");
  parent_node.append(summary_node);
  summary_nodes.set(date_string, summary_node);

  const add_button = document.createElement("button");
  add_button.innerText = "Add meal";

  // Do this outside callback or else date may have been modified lol
  const date_unix_time = date.getTime();
  const tz_offs = date.getTimezoneOffset();
  add_button.onclick = async () => {
    const new_meal = await meals.add({
      timestamp_utc: date_unix_time,
      tz_offs_min: tz_offs,
    });
    window.location.href = makeMealUrl(new_meal.id);
  };
  parent_node.append(add_button);

  meals_node.append(parent_node);

  return date_meals;
}

function stepDateBackwards(d) {
  d.setDate(d.getDate() - 1);
}

function initDateNodes() {
  let d = new Date();

  // Dates are more consistent at midnight
  d.setHours(0);
  d.setMinutes(0);
  d.setSeconds(0);

  addDateNode(d, "Today");
  stepDateBackwards(d);

  addDateNode(d, "Yesterday");
  stepDateBackwards(d);

  for (let i = 0; i < 5; ++i) {
    addDateNode(d);
    stepDateBackwards(d);
  }
}

function updateSummaryNodes() {
  const day_summaries = new Map();

  for (const meal of meals.items) {
    const key = new Date(meal.timestamp_utc).toLocaleDateString();
    if (!day_summaries.has(key)) {
      day_summaries.set(key, {
        summary_complete: true,
        properties: new Map(),
      });
    }

    const day_summary = day_summaries.get(key);

    if (meal.summary_complete !== true) {
      day_summary.summary_complete = false;
    }
    for (const property_summary of meal.summary) {
      const property_key = property_summary.property_id;

      let existing = day_summary.properties.get(property_key, 0);
      if (existing === undefined) {
        existing = 0;
      }

      day_summary.properties.set(
        property_key,
        existing + property_summary.value,
      );
    }
  }

  for (const [date_key, day_summary] of day_summaries.entries()) {
    const summary_node = summary_nodes.get(date_key);

    if (summary_node === undefined) {
      continue;
    }

    // Match format of meal.summary for updateSummaryNodeApi
    // [ { property_id, value }, ... ]
    const day_properties_array = Array.from(
      day_summary.properties,
      ([property_id, value]) => ({ property_id, value }),
    );
    const summary_complete = day_summary.summary_complete;

    property_helpers.updateSummaryNode(
      summary_node,
      day_properties_array,
      summary_complete,
      properties,
    );
  }
}

async function init() {
  header.prependHeaderToBody();

  initDateNodes();

  await Promise.all([
    meals.initFromServer(),
    dishes.initFromServer(),
    properties.initFromServer(),
  ]);

  // Do explicitly after init
  for (const meal of meals.items) {
    appendMealToList(meal);
  }

  updateSummaryNodes();

  meals.new_callback = appendMealToList;

  fully_initialized = true;
}

window.onload = init;
window.onpageshow = async function () {
  if (fully_initialized) {
    await meals.update();
    updateSummaryNodes();
  }
};
