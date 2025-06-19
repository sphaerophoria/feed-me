function calcDepth(property, properties) {
  var depth = 0;

  while (property.parent_id !== null && property.parent_id !== undefined) {
    property = properties.getById(property.parent_id);
    depth += 1;
  }

  return depth;
}

function sortKey(property, properties) {
  var stack = [property.id];

  while (property.parent_id !== null && property.parent_id !== undefined) {
    property = properties.getById(property.parent_id);
    stack.push(property.id);
  }

  stack.reverse();
  return stack;
}

function updateSummaryNode(node, summary, summary_complete, properties) {
  const fragment = document.createDocumentFragment();

  const node_list = [];

  for (const entry of summary) {
    const property = properties.getById(entry.property_id);

    const name_col = document.createElement("div");
    const value_col = document.createElement("div");

    name_col.innerText = property.name;
    value_col.innerText = entry.value.toFixed(2);
    value_col.style.justifySelf = "end";
    value_col.style.textAlign = "end";

    name_col.style.marginLeft = `${calcDepth(property, properties) * 2}em`;

    node_list.push([name_col, value_col, sortKey(property, properties)]);
  }

  // Elements are expected to be displayed in a CSS grid. Sort in a way where
  // child nodes are adjacent to parent nodes. Indentation is handled by
  // marginLeft above. Keep ordering of child nodes
  node_list.sort((a, b) => {
    const a_key = a[2];
    const b_key = b[2];

    for (let i = 0; i < Math.min(a_key.length, b_key.length); ++i) {
      if (a_key[i] < b_key[i]) {
        return -1;
      } else if (a_key[i] > b_key[i]) {
        return 1;
      }
    }

    // If all entries were the same, we are sorting a parent vs a child.
    // Parents (shorter keys) come first
    if (a_key.length < b_key.length) {
      return -1;
    } else {
      return 1;
    }
  });

  for (const nodes of node_list) {
    fragment.append(nodes[0]);
    fragment.append(nodes[1]);
  }

  node.replaceChildren(fragment);
  node.classList.toggle("complete", summary_complete);
}

export { calcDepth, updateSummaryNode };
