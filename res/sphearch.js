class SearchBarData {
  constructor() {
    this.selected_idx = null;
    this.items = [];
    this.autoselect = false;
  }

  setSearchResults(results) {
    this.items = results;
    if (this.autoselect === true && results.length > 0) {
      this.setSelected(0);
    } else {
      this.setSelected(null);
    }
  }

  setSelected(i) {
    const old_idx = this.selected_idx;
    this.selected_idx = i;
    this.updateHighlight(old_idx, this.selected_idx);
  }

  navigateDown() {
    const old_idx = this.selected_idx;

    if (this.selected_idx === null) {
      this.selected_idx = 0;
    } else if (this.selected_idx < this.items.length - 1) {
      this.selected_idx += 1;
    }

    this.updateHighlight(old_idx, this.selected_idx);
  }

  navigateUp() {
    const old_idx = this.selected_idx;

    if (this.selected_idx === 0) {
      this.selected_idx = null;
    } else if (this.selected_idx !== null) {
      this.selected_idx -= 1;
    }

    this.updateHighlight(old_idx, this.selected_idx);
  }

  updateHighlight(old_idx, new_idx) {
    if (old_idx !== null) {
      this.items[old_idx].classList.remove("search_highlight");
    }

    if (new_idx !== null) {
      this.items[new_idx].classList.add("search_highlight");
    }
  }
}

class Sphearch extends HTMLElement {
  constructor() {
    super();

    this.search_bar_data = new SearchBarData();
    this.search_results = null;
    this.on_select = null;
    this.on_new = null;
  }

  connectedCallback() {
    this.search_box = document.createElement("input");
    this.search_box.type = "search";

    // FIXME: Surely this will come up again
    switch (this.getAttribute("autoselect")) {
      case "true":
      case "":
        this.search_bar_data.autoselect = true;
        break;
      case "false":
        break;
      default:
        console.warn("Unexpected autoselect value on sphearch-bar");
        break;
    }

    this.search_box.placeholder = this.getAttribute("placeholder");

    this.search_box.oninput = (ev) => {
      const new_results = this.search_results(ev.target.value);
      this.setSearchResults(new_results);
    };

    this.addEventListener("keydown", (ev) => {
      switch (ev.key) {
        case "ArrowDown":
          this.search_bar_data.navigateDown();
          ev.preventDefault();
          break;
        case "ArrowUp":
          this.search_bar_data.navigateUp();
          ev.preventDefault();
          break;
        case "Enter":
          this.executeSelection();
          break;
      }
    });

    this.words_div = document.createElement("div");

    this.append(this.search_box);
    this.append(this.words_div);
  }

  executeSelection() {
    if (this.search_bar_data.selected_idx !== null && this.on_select !== null) {
      this.on_select(this.search_bar_data.selected_idx);
    } else if (this.on_new !== null) {
      this.on_new(this.search_box.value);
    }
  }

  setSearchResults(words) {
    const fragment = document.createDocumentFragment();
    const data = [];
    for (let i = 0; i < words.length; i++) {
      const word = words[i];
      const div = document.createElement("div");
      div.classList.add("sphearch-bar-result");
      div.innerText = word;
      div.onclick = () => {
        this.executeSelection();
      };
      div.onmouseenter = () => {
        this.search_bar_data.setSelected(i);
      };
      fragment.append(div);
      data.push(div);
    }

    this.words_div.replaceChildren(fragment);
    this.search_bar_data.setSearchResults(data);
  }

  clear() {
    this.search_box.value = "";
    this.setSearchResults(this.search_results(""));
  }
}

const sheet = new CSSStyleSheet();
sheet.replaceSync(
  `
  sphearch-bar {
    display: block;
  }

  sphearch-bar > * {
    width: 100%;
  }

  .sphearch-bar-result {
    margin-left: 1em;
    margin-right;
  }

  .sphearch-bar-result {
    padding-left: 1em;
    padding-right: 1em;
  }

  .search_highlight {
    background: #5555ff;
  }
  `,
);

document.adoptedStyleSheets.push(sheet);
window.customElements.define("sphearch-bar", Sphearch);
