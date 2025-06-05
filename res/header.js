function prependHeaderToBody() {
  const header = document.createElement("div");
  const pages = [
    ["Ingredients", "/index.html"],
    ["Properties", "/properties.html"],
    ["Dishes", "/dishes.html"],
    ["Meals", "/meals.html"],
  ];

  for (const page of pages) {
    const name = page[0];
    const url = page[1];

    const a = document.createElement("a");
    a.innerText = name + " ";
    a.href = url;
    a.classList.add();

    header.append(a);
  }
  document.body.prepend(header);
}

export { prependHeaderToBody };
