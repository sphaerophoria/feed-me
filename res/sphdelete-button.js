class SphdeleteButton extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    this.innerHTML = "";

    const delete_button = document.createElement("input");
    delete_button.type = "image";
    delete_button.src = "delete.svg";
    this.append(delete_button);
  }
}

{
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(
    `
      sphdelete-button {
        display: block;
        width: fit-content;
        filter: saturate(20%);
        width: 1em;
        min-width: 1em;
        height: 1em;
        min-height: 1em;
      }

      sphdelete-button input {
        display: block;
        background: unset;
        width: 100%;
        height: 100%;
        padding: 0em;
        margin: 0px;
      }

      sphdelete-button:hover{
        filter: unset;
      }
    `,
  );
  document.adoptedStyleSheets.push(sheet);
}
window.customElements.define("sphdelete-button", SphdeleteButton);
