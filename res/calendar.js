class Calendar extends HTMLElement {
  connectedCallback() {
    const table = document.createElement("table");
    const header = document.createElement("thead");
    table.append(header);

    const header_row = document.createElement("tr");
    header.append(header_row);

    for (const day of [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
    ]) {
      const th = document.createElement("th");
      th.innerText = day;
      header_row.append(th);
    }

    const body = document.createElement("tbody");
    table.append(body);

    for (let i = 0; i < 6; i++) {
      const row = document.createElement("tr");
      body.append(row);

      for (let j = 0; j < 7; j++) {
        const cell = document.createElement("td");
        // date
        cell.append(document.createElement("div"));
        // Content
        cell.append(document.createElement("div"));
        row.append(cell);
      }
    }

    this.append(table);
  }

  get elems() {
    return Array.from(
      this.querySelectorAll("table > tbody > tr > td > div:nth-child(2)"),
    );
  }

  updateDates(date) {
    const it = new Date(date.getTime());
    it.setDate(1);
    it.setHours(0);
    it.setMinutes(0);
    it.setSeconds(0);

    const first_day_idx = it.getDay();
    const month_idx = it.getMonth();

    let date_elems = Array.from(
      this.querySelectorAll("table > tbody > tr > td > div:nth-child(1)"),
    );
    let content_elems = this.elems;

    for (const elem of date_elems) {
      elem.innerHTML = "";
    }

    for (const elem of content_elems) {
      elem.innerHTML = "";
    }

    date_elems = date_elems.slice(first_day_idx);
    content_elems = content_elems.slice(first_day_idx);

    let elem_idx = 0;

    while (it.getMonth() == month_idx) {
      const it_date = it.getDate();

      const date_elem = date_elems[elem_idx];
      date_elem.innerText = it_date;
      const content_elem = content_elems[elem_idx];

      elem_idx += 1;

      const tz_offs_s = it.getTimezoneOffset() * 60;
      content_elem.setAttribute("timestamp-start", it.getTime() - tz_offs_s);

      // Both for timestamp-end and loop iteration
      it.setDate(it_date + 1);

      content_elem.setAttribute("timestamp-end", it.getTime() - tz_offs_s);

      const event = new Event("sphcalendar-update", { bubbles: true });
      content_elem.dispatchEvent(event);
    }
  }
}

{
  const css = new CSSStyleSheet();
  css.replaceSync(`
    sphaero-calendar > table > tbody > tr > td {
      height: 5em;
      border-style: solid;
    }
  `);
  document.adoptedStyleSheets.push(css);
}
window.customElements.define("sphaero-calendar", Calendar);
