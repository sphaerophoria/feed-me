#!/usr/bin/env python3

import time
import tempfile
import subprocess
import signal
import json
from http.client import HTTPConnection
from pathlib import Path

PORT = 9990

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


def set_ingredient_serving_sizes(ingredient_id, serving_size_g, serving_size_ml, serving_size_pieces):
    send_request("PUT", "/ingredients/" + str(ingredient_id), {
        "serving_size_g": serving_size_g,
        "serving_size_ml": serving_size_ml,
        "serving_size_pieces": serving_size_pieces,
    })


def add_property(name):
    p = send_request("PUT", "/properties", {
        "name": name,
    })
    assert(p is not None)
    return p


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

def get_ingredients():
    ret =  send_request("GET", "/ingredients", None)
    assert(ret is not None)
    return ret

def get_ingredient(id):
    ret =  send_request("GET", "/ingredients/" + str(id), None)
    assert(ret is not None)
    return ret

def get_properties():
    ret = send_request("GET", "/properties", None)
    assert(ret is not None)
    return ret

def test_ingredient(ingredient, expected_id, expected_ss_g, expected_ss_ml, expected_ss_pieces, expected_properties):
    common_tests = [
            ["id", expected_id],
            ["serving_size_g", expected_ss_g],
            ["serving_size_ml", expected_ss_ml],
            ["serving_size_pieces", expected_ss_pieces],
    ]
    assert("properties" not in ingredient)

    for key, value in common_tests:
        assert(ingredient[key] == value)

    ingredient_w_properties = get_ingredient(expected_id)

    for key, value in common_tests:
        assert(ingredient_w_properties[key] == value)

    sorted_props = sorted(ingredient_w_properties["properties"], key=lambda p: p["property_id"])

    for expected, actual in zip(expected_properties, sorted_props):
        assert(actual["ingredient_id"] == expected_id)
        assert(actual["property_id"] == expected[0])
        assert(actual["value"] == expected[1])

def test_endpoints():
    egg = add_ingredient("egg")
    set_ingredient_serving_sizes(egg["id"], 50, 0, 1)

    bread = add_ingredient("bread")
    set_ingredient_serving_sizes(bread["id"], 51, 0, 2)

    cream_cheese = add_ingredient("cream_cheese")
    set_ingredient_serving_sizes(cream_cheese["id"], 28, 0, 0)

    calories = add_property("calories")
    fat = add_property("fat")
    protein = add_property("protein")

    options = [
            # Serving size 1 egg 50g
            [egg, calories, 70],
            [egg, protein, 6],
            [egg, fat, 5],

            # 2 slices 51g
            [bread, calories, 120],
            [bread, protein, 5],
            [bread, fat, 1],

            # 28g
            [cream_cheese, calories, 70],
            [cream_cheese, protein, 2],
            [cream_cheese, fat, 6],
    ]

    for [ingredient, prop, value] in options:
        add_ingredient_property(ingredient["id"], prop["id"], value)

    ingredients = sorted(get_ingredients(), key=lambda i: i["id"])

    if len(ingredients) != 3:
        raise RuntimeError("Unexpected number of ingredients")

    test_ingredient(ingredients[0], egg["id"], 50, 0, 1, [
        [calories["id"], 70],
        [fat["id"], 5],
        [protein["id"], 6],
    ])

    test_ingredient(ingredients[1], bread["id"], 51, 0, 2, [
        [calories["id"], 120],
        [fat["id"], 1],
        [protein["id"], 5],
    ])

    test_ingredient(ingredients[2], cream_cheese["id"], 28, 0, 0, [
        [calories["id"], 70],
        [fat["id"], 6],
        [protein["id"], 2],
    ])

    properties = sorted(get_properties(), key=lambda p: p["id"])
    assert(len(properties) == 3)

    assert(properties[0]["name"] == "calories")
    assert(properties[1]["name"] == "fat")
    assert(properties[2]["name"] == "protein")

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
