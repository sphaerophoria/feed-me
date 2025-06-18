#!/usr/bin/env python3

import time
import tempfile
import copy
import subprocess
import signal
import json
import datetime
from http.client import HTTPConnection
from pathlib import Path

PORT = 42069

def send_request(method, endpoint, body_dict):
    conn = HTTPConnection("localhost", PORT)

    body = None
    if body_dict != None:
        body = json.dumps(body_dict)

    conn.request(method, endpoint, body=body)
    response = conn.getresponse()

    if (response.status != 200):
        raise RuntimeError("Unexpected failure")

    response_body = response.read()

    if (len(response_body) != 0):
        return json.loads(response_body)

    return None


def add_ingredient(name):
    ingredient = send_request("PUT", "/ingredients", {
        "name": name,
    })
    assert(ingredient is not None)
    return ingredient

def add_ingredient_category(ingredient_id, name):
    body = {}
    if (name is not None):
        body["name"] = name

    if (ingredient_id is not None):
        body["ingredient_id"] = ingredient_id

    category = send_request("PUT", "/ingredient_categories", body)
    assert (category is not None)
    return category

def add_ingredient_to_category(ingredient_id, category_id):
    send_request("PUT", "/ingredient_category_mappings", {
        "ingredient_id": ingredient_id,
        "category_id": category_id,
    })

def get_ingredient_category(category_id):
    category = send_request("GET", "/ingredient_categories/" + str(category_id), None)
    assert (category is not None)
    return category

def delete_ingredient_category_mapping(mapping_id):
    category = send_request("DELETE", "/ingredient_category_mappings/" + str(mapping_id), None)

def get_ingredient_categories():
    categories = send_request("GET", "/ingredient_categories", None)
    assert (categories is not None)
    categories.sort(key=lambda c: c["id"])
    return categories

def modify_ingredient_category(category_id, params):
    send_request("PUT", "/ingredient_categories/" + str(category_id), params)

def set_ingredient_serving_sizes(ingredient_id, serving_size_g, serving_size_ml, serving_size_pieces):
    send_request("PUT", "/ingredients/" + str(ingredient_id), {
        "serving_size_g": serving_size_g,
        "serving_size_ml": serving_size_ml,
        "serving_size_pieces": serving_size_pieces,
    })


def mark_ingredient_complete(ingredient_id, completed):
    send_request("PUT", "/ingredients/" + str(ingredient_id), {
        "fully_entered": completed,
    })

def add_property(name, parent_id):
    p = send_request("PUT", "/properties", {
        "name": name,
        "parent_id": parent_id,
    })
    assert(p is not None)
    return p

def modify_property(prop_id, name):
    send_request("PUT", "/properties/" + str(prop_id), {
        "name": name,
    })


def add_ingredient_property(ingredient_id, property_id, value):
    ingredient_property = send_request("PUT", "/ingredient_properties", {
        "ingredient_id": ingredient_id,
        "property_id": property_id,
    })

    if ingredient_property is None:
        raise RuntimeError("No ingredient property")

    send_request("PUT", "/ingredient_properties/" + str(ingredient_property["id"]), {
        "value": value,
    })

def add_dish(name):
    dish = send_request("PUT", "/dishes", {
        "name": name,
    })
    assert(dish is not None)
    return dish

def get_dishes():
    ret =  get_endpoint("/dishes")
    ret.sort(key=lambda d: d["id"])
    return ret

def modify_dish(dish_id, name):
    send_request("PUT", "/dishes/" + str(dish_id), {
        "name": name,
    })

def add_meal(timestamp, timezone):
    meal = send_request("PUT", "/meals", {
        "timestamp_utc": timestamp,
        "tz_offs_min": timezone
    })
    assert(meal is not None)
    return meal

def add_meal_dish(meal_id, dish_id):
    meal_dish = send_request("PUT", "/meal_dishes", {
        "meal_id": meal_id,
        "dish_id": dish_id,
    })
    assert(meal_dish is not None)
    return meal_dish

def delete_meal_dish(meal_dish_id):
    send_request("DELETE", "/meal_dishes/" + str(meal_dish_id), None)

def add_meal_dish_ingredient(meal_dish_id, ingredient_id):
    meal_dish_ingredient = send_request("PUT", "/meal_dish_ingredients", {
        "meal_dish_id": meal_dish_id,
        "ingredient_id": ingredient_id,
    })
    assert(meal_dish_ingredient is not None)
    return meal_dish_ingredient

def modify_meal_dish_ingredient(mdi_id, quantity, unit):
    send_request("PUT", "/meal_dish_ingredients/" + str(mdi_id), {
        "quantity": quantity,
        "unit": unit,
    })

def get_endpoint(endpoint):
    ret =  send_request("GET", endpoint, None)
    assert(ret is not None)
    return ret

def get_ingredients():
    ret =  send_request("GET", "/ingredients", None)
    assert(ret is not None)
    for ingredient in ret:
        ingredient["category_mappings"].sort(key=lambda c: c["id"])
    return ret

def get_ingredient(id):
    ret =  send_request("GET", "/ingredients/" + str(id), None)
    assert(ret is not None)
    ret["category_mappings"].sort(key=lambda c: c["id"])
    return ret

def get_properties():
    ret = send_request("GET", "/properties", None)
    assert(ret is not None)
    return ret

def get_meals():
    meals = get_endpoint("/meals")
    for meal in meals:
        meal["dishes"].sort(key=lambda d: d["dish_id"])
        meal["summary"].sort(key=lambda s: s["property_id"])
    meals.sort(key=lambda m: m["id"])
    return meals

def get_meal(meal_id):
    meal = get_endpoint("/meals/" + str(meal_id))
    meal["dishes"].sort(key=lambda d: d["dish_id"])
    meal["summary"].sort(key=lambda s: s["property_id"])
    return meal

def delete_meal(meal_id):
    send_request("DELETE", "/meals/" + str(meal_id), None)

def test_ingredient(ingredient, expected_id, expected_ss_g, expected_ss_ml, expected_ss_pieces, expected_fully_entered, expected_categories, expected_properties):
    assert("properties" not in ingredient)

    ingredient_w_properties = get_ingredient(expected_id)
    assert(ingredient_w_properties["id"] == expected_id)
    assert(ingredient_w_properties["serving_size_g"] == expected_ss_g)
    assert(ingredient_w_properties["serving_size_ml"] == expected_ss_ml)
    assert(ingredient_w_properties["serving_size_pieces"] == expected_ss_pieces)
    assert(ingredient["fully_entered"] == expected_fully_entered)

    for expected_category_id, mapping in zip(expected_categories, ingredient_w_properties["category_mappings"]):
        assert(expected_category_id == mapping["ingredient_category_id"])

    assert(len(ingredient_w_properties["category_mappings"]) == len(expected_categories))

    sorted_props = sorted(ingredient_w_properties["properties"], key=lambda p: p["property_id"])

    for expected, actual in zip(expected_properties, sorted_props):
        assert(actual["ingredient_id"] == expected_id)
        assert(actual["property_id"] == expected[0])
        assert(actual["value"] == expected[1])

    del ingredient_w_properties["properties"]
    assert(ingredient_w_properties == ingredient)

def init_meal_1(today, timezone, egg_on_bread, egg, bread):
    meal_1 = add_meal(today, timezone)
    add_egg_on_bread_to_meal(meal_1["id"], egg_on_bread, egg, bread)
    return meal_1

def init_meal_2(today, timezone, egg_on_bread, bread_and_cheese, egg, bread, cream_cheese):
    meal = add_meal(today, timezone)
    add_egg_on_bread_to_meal(meal["id"], egg_on_bread, egg, bread)
    add_bread_and_cheese_to_meal(meal["id"], bread_and_cheese, bread, cream_cheese)
    return meal

def add_egg_on_bread_to_meal(meal_id, egg_on_bread, egg, bread):
    meal_1_dish = add_meal_dish(meal_id, egg_on_bread["id"])
    meal_1_egg = add_meal_dish_ingredient(meal_1_dish["id"], egg["id"])
    modify_meal_dish_ingredient(meal_1_egg["id"], 2, "pieces")

    meal_1_bread = add_meal_dish_ingredient(meal_1_dish["id"], bread["id"])
    modify_meal_dish_ingredient(meal_1_bread["id"], 2, "pieces")

def add_bread_and_cheese_to_meal(meal_id, bread_and_cheese, bread, cream_cheese):
    dish = add_meal_dish(meal_id, bread_and_cheese["id"])
    dish_bread = add_meal_dish_ingredient(dish["id"], bread["id"])
    modify_meal_dish_ingredient(dish_bread["id"], 2, "pieces")

    dish_cheese = add_meal_dish_ingredient(dish["id"], cream_cheese["id"])
    modify_meal_dish_ingredient(dish_cheese["id"], 50, "mass")

def test_meal(meal, today, timezone, summary_complete, summary, dish_ids, dish_ingredients=None):
    assert(meal["timestamp_utc"] == today)
    assert(meal["tz_offs_min"] == timezone)
    assert(len(meal["dishes"]) == len(dish_ids))
    for i in range(0, len(dish_ids)):
        dish = meal["dishes"][i]
        expected_id = dish_ids[i]
        assert(dish["dish_id"] == expected_id)

        if dish_ingredients is not None:
            expected_ingredients = dish_ingredients[i]
            retreived_ingredients = dish["ingredients"]
            assert(len(expected_ingredients) == len(retreived_ingredients))

            for expected_ingredient, retrieved_ingredient in zip(expected_ingredients, retreived_ingredients):
                for key, value in expected_ingredient.items():
                    assert(retrieved_ingredient[key] == value)
        else:
            assert(dish["ingredients"] == [])


    assert(len(meal["summary"]) == len(summary))

    for retrieved, expected in zip (meal["summary"], summary):
        assert(abs(float(retrieved["value"]) - float(expected["value"])) < 1e-3)
        assert(retrieved["property_id"] == expected["property_id"])

    assert(meal["summary_complete"] == summary_complete)

def removed_mappings(item):
    ret = copy.deepcopy(item)
    del ret["mappings"]
    return ret

def test_endpoints():
    egg = add_ingredient("egg")
    set_ingredient_serving_sizes(egg["id"], 50, 0, 1)

    bread = add_ingredient("bread")
    set_ingredient_serving_sizes(bread["id"], 51, 0, 2)

    bread_category = add_ingredient_category(bread["id"], None);
    other_category = add_ingredient_category(None, "test category w/ typo");
    modify_ingredient_category(other_category["id"], {
        "name": "test category",
    })

    cream_cheese = add_ingredient("cream_cheese")
    set_ingredient_serving_sizes(cream_cheese["id"], 28, 0, 0)

    bagel = add_ingredient("bagel")
    add_ingredient_to_category(bagel["id"], bread_category["id"])

    calories = add_property("calories", None)
    fat = add_property("fat", None)
    saturated_fat = add_property("saturated fat", fat["id"])
    protein = add_property("protein_with_typo", None)
    modify_property(protein["id"], "protein")

    options = [
            # Serving size 1 egg 50g
            [egg, calories, 70],
            [egg, protein, 6.1],
            [egg, fat, 5],

            # 2 slices 51g
            [bread, calories, 120],
            [bread, protein, 5],
            [bread, fat, 1],

            # 28g
            [cream_cheese, calories, 70],
            [cream_cheese, protein, 2],
            [cream_cheese, fat, 5],
            [cream_cheese, saturated_fat, 1],
    ]

    for [ingredient, prop, value] in options:
        add_ingredient_property(ingredient["id"], prop["id"], value)

    mark_ingredient_complete(bread["id"], True)
    mark_ingredient_complete(egg["id"], True)

    egg_on_bread = add_dish("egg on bread")
    bread_and_cheese = add_dish("bread and cheese")
    modify_dish(bread_and_cheese["id"], "breadd and cheese")

    # June 10, 2025 at whatever time I happened to get the timestamp, like,
    # 13:06 or something
    today = 1749585958
    # PDT -7
    timezone = -420

    meal_1 = init_meal_1(today, timezone, egg_on_bread, egg, bread)
    meal_2 = init_meal_2(today, timezone, egg_on_bread, bread_and_cheese, egg, bread, cream_cheese)

    ingredients = sorted(get_ingredients(), key=lambda i: i["id"])

    if len(ingredients) != 4:
        raise RuntimeError("Unexpected number of ingredients")

    test_ingredient(ingredients[0], egg["id"], 50, 0, 1, True, [], [
        [calories["id"], 70],
        [fat["id"], 5],
        [protein["id"], 6.1],
    ])

    test_ingredient(ingredients[1], bread["id"], 51, 0, 2, True, [bread_category["id"]], [
        [calories["id"], 120],
        [fat["id"], 1],
        [protein["id"], 5],
    ])

    test_ingredient(ingredients[2], cream_cheese["id"], 28, 0, 0, False, [], [
        [calories["id"], 70],
        [fat["id"], 5],
        [saturated_fat["id"], 1],
        [protein["id"], 2],
    ])

    # idgaf about the bagel, it has no parameters set

    assert bread_category["name"] == "bread"
    assert other_category["name"] == "test category w/ typo"

    retrieved_bread_category = get_ingredient_category(bread_category["id"])
    assert(retrieved_bread_category["id"] == bread_category["id"])
    assert(retrieved_bread_category["name"] == "bread")
    assert(len(retrieved_bread_category["mappings"]) == 2)
    assert(retrieved_bread_category["mappings"][0]["ingredient_id"] == bread["id"])
    assert(retrieved_bread_category["mappings"][1]["ingredient_id"] == bagel["id"])
    assert(retrieved_bread_category["fully_entered"] == False)

    retrieved_other_category = get_ingredient_category(other_category["id"])
    assert(retrieved_other_category["name"] == "test category")
    assert(retrieved_other_category["fully_entered"] == True)

    retrieved_ingredient_categories = get_ingredient_categories();
    assert(len(retrieved_ingredient_categories) == 2)
    assert(retrieved_ingredient_categories[0] == removed_mappings(retrieved_bread_category))
    assert(retrieved_ingredient_categories[1] == removed_mappings(retrieved_other_category))

    properties = sorted(get_properties(), key=lambda p: p["id"])
    assert(len(properties) == 4)

    assert(properties[0]["name"] == "calories")
    assert(properties[0].get("parent_id", None) == None)
    assert(properties[1]["name"] == "fat")
    assert(properties[1].get("parent_id", None) == None)
    assert(properties[2]["name"] == "saturated fat")
    assert(properties[2].get("parent_id", None) == fat["id"])
    assert(properties[3]["name"] == "protein")
    assert(properties[3].get("parent_id", None) == None)

    meals = get_meals()

    meal_1_expected_properties = [
        { "property_id": calories["id"], "value": 260 },
        { "property_id": fat["id"], "value": 11 },
        { "property_id": protein["id"], "value": 17.2 },
    ]

    test_meal(meals[0], today, timezone, True, meal_1_expected_properties , [
        egg_on_bread["id"]
    ])

    meal_2_expected_properties = [
        {'property_id': calories["id"], 'value': 505},
        {'property_id': fat["id"], 'value': 22.714},
        {'property_id': saturated_fat["id"], 'value': 1.786},
        {'property_id': protein["id"], 'value': 25.771}
    ]

    test_meal(meals[1], today, timezone, False, meal_2_expected_properties, [
        egg_on_bread["id"],
        bread_and_cheese["id"],
    ])

    meal_1_retreived = get_meal(meal_1["id"])

    egg_on_bread_ingredients = [
        {'ingredient_id': egg["id"], 'quantity': 2, 'unit': 'pieces'},
        {'ingredient_id': bread["id"], 'quantity': 2, 'unit': 'pieces'}
    ]

    bread_and_cheese_ingredients = [
        {'ingredient_id': bread["id"], 'quantity': 2, 'unit': 'pieces'},
        {'ingredient_id': cream_cheese["id"], 'quantity': 50, 'unit': 'mass'}

    ]

    test_meal(meal_1_retreived, today, timezone, True, meal_1_expected_properties , [
        egg_on_bread["id"]
    ], [
        egg_on_bread_ingredients,
    ])

    meal_2_retreived = get_meal(meal_2["id"])
    test_meal(meal_2_retreived, today, timezone, False, meal_2_expected_properties , [
        egg_on_bread["id"],
        bread_and_cheese["id"],
    ], [
        egg_on_bread_ingredients,
        bread_and_cheese_ingredients,
    ])

    delete_meal_dish(meals[1]["dishes"][1]["id"])

    meals = get_meals()
    assert(len(meals[1]["dishes"]))
    assert(meals[1]["dishes"][0]["dish_id"] == egg_on_bread["id"])

    delete_meal(meal_2["id"]);
    meals = get_meals()

    assert(len(meals) == 1)
    assert(meals[0]["id"] == meal_1["id"])

    dishes = get_dishes()
    assert(len(dishes) == 2)
    assert(dishes[0]["name"] == "egg on bread")
    assert(dishes[1]["name"] == "breadd and cheese")

    delete_ingredient_category_mapping(retrieved_bread_category["mappings"][1]["id"])
    new_bread_category = get_ingredient_category(bread_category["id"])
    assert(len(new_bread_category["mappings"]) ==  1)
    assert(new_bread_category["mappings"][0]["ingredient_id"] ==  bread["id"])


def main(spawn_process):
    with tempfile.TemporaryDirectory() as d:
        temp_path = Path(d)
        if spawn_process:
            process = subprocess.Popen([
                "zig-out/bin/feed_me",
                "--db-path", str(temp_path / "db.db"),
                "--port", str(PORT),
            ])
        else:
            process = None

        try:
            test_endpoints()
        finally:
            if process:
                process.send_signal(signal.SIGINT)
                process.wait()

if __name__ == '__main__':
    main(True)
