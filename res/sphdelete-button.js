class SphdeleteButton extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    const delete_button = document.createElement("input");
    delete_button.type = "image";
    delete_button.src = "delete.svg";
    this.append(delete_button);
  }
}

const sheet = new CSSStyleSheet();
sheet.replaceSync(
  `
    sphdelete-button {
      /* Div by default will add padding (line-height) to the content box which
       * messes up placement in a grid. We could set line-height to 0 instead,
       * but if we are trying to expose the input box as closesly as possible,
       * this is a better representation of that. Downside is that you can no
       * longer directly set width/height/etc. on the sphdelete-button element,
       * which might be confusing for external users.
       */
      display: contents;
    }

    sphdelete-button input {
      /* Prevent adopting block type which extends
       * all the way to the right edge of the parent
       * div
       */
      display: inline-block;
      background: unset;
      width: 1em;
      height: 1em;
      padding: 0em;
      margin: 0px;
      filter: saturate(20%);
    }

    sphdelete-button input:hover{
      filter: unset;
    }
  `,
);
document.adoptedStyleSheets.push(sheet);
window.customElements.define("sphdelete-button", SphdeleteButton);
