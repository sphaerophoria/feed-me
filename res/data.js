class RemoteItemArray {
  constructor(url) {
    this.url = url;
    this.items = [];
    this.new_callback = null;
  }

  async initFromServer() {
    const response = await fetch(this.url);
    this.items = await response.json();
    if (this.new_callback !== null) {
      for (const item of this.items) {
        this.new_callback(item);
      }
    }
  }

  async add(params) {
    const response = await fetch(this.url, {
      method: "PUT",
      body: params !== null ? JSON.stringify(params) : null,
    });
    const json = await response.json();
    this.items.push(json);
    if (this.new_callback !== null) {
      this.new_callback(json);
    }

    return json;
  }

  getById(id) {
    for (const elem of this.items) {
      if (elem.id == id) return elem;
    }

    return null;
  }
}

function makeIngredients() {
  return new RemoteItemArray("/ingredients");
}

function makeProperties() {
  return new RemoteItemArray("/properties");
}

export { makeIngredients, makeProperties };
