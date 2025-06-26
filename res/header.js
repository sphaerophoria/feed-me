class PageHeader extends HTMLElement {
  connectedCallback() {
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

      this.append(a);
    }
  }
}

window.customElements.define("spheader-bar", PageHeader);
