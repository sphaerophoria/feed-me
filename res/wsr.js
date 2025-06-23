const wasm_url = document.currentScript.getAttribute("wasm-url");
/** @type WebAssembly.WebAssemblyInstantiatedSource */
let wasm_obj = null;

let current_node = null;

function print(ptr, len) {
  if (wasm_obj === null) return;
  const arr = new Uint8Array(wasm_obj.instance.exports.memory.buffer, ptr, len);
  const decoder = new TextDecoder();
  const s = decoder.decode(arr);
  console.log(s);
}

function getWasmString(wasm_obj, ptr, len) {
  if (len == 0) return "";
  const output_buf = new Uint8Array(wasm_obj.instance.exports.memory.buffer, ptr, len);
  const decoder = new TextDecoder();
  return decoder.decode(output_buf);
}

function replaceSelfContent(
  content_ptr, content_len,
  attribute_ptr, attribute_len,
) {
  const content = getWasmString(wasm_obj, content_ptr, content_len);
  const attribute = getWasmString(wasm_obj, attribute_ptr, attribute_len);

  current_node[attribute] = content;
}

function replaceElemContent(
  elem_id_ptr, elem_id_len,
  content_ptr, content_len,
  attribute_ptr, attribute_len,
) {
  const elem_id = getWasmString(wasm_obj, elem_id_ptr, elem_id_len);
  const content = getWasmString(wasm_obj, content_ptr, content_len);
  const attribute = getWasmString(wasm_obj, attribute_ptr, attribute_len);

  const node = document.getElementById(elem_id);
  console.log(elem_id, attribute, content);
  node[attribute] = content;
}

function deleteElemByQuery(query_ptr, query_len) {
  const query = getWasmString(wasm_obj, query_ptr, query_len);

  const nodes = document.querySelectorAll(query);
  for (const node of nodes) {
    node.remove();
  }
}

function setWasmInputBuffer(s) {
  const encoder = new TextEncoder();
  const data = encoder.encode(s);

  wasm_obj.instance.exports.allocateInputBuffer(data.length);
  const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
  const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, data.length);
  input_buffer.set(data);

}

function getSelfProperty(property_ptr, property_len) {
  const prop = getWasmString(wasm_obj, property_ptr, property_len);
  setWasmInputBuffer(current_node[prop]);
}

function getSelfAttribute(property_ptr, property_len) {
  //FIXME: Wrong name
  const prop = getWasmString(wasm_obj, property_ptr, property_len);
  setWasmInputBuffer(current_node.getAttribute(prop));
}

function callOnResponse(fetch_promise, elem, wasm_target, arg) {
  fetch_promise.then((response) => response.bytes()).then((body) => {
    let data = null;
    if (arg.length !== 0) {
      const encoder = new TextEncoder();
      data = encoder.encode(arg);
    } else if (body.length !== 0) {
      data = body;
    }

    if (data != null) {
      wasm_obj.instance.exports.allocateInputBuffer(data.length);
      const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
      const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, data.length);
      input_buffer.set(data);
    }

    callWasmTarget(elem, wasm_target);
  });
}

function requestFetch(
  url_ptr, url_len,
  body_ptr, body_len,
  method_ptr, method_len,
  // FIXME: Can we just give a fn pointer directly?
  callback_ptr, callback_len,
  arg_ptr, arg_len,
) {
  const url = getWasmString(wasm_obj, url_ptr, url_len);
  const body = getWasmString(wasm_obj, body_ptr, body_len);
  const method = getWasmString(wasm_obj, method_ptr, method_len);
  const callback = getWasmString(wasm_obj, callback_ptr, callback_len);
  const arg = getWasmString(wasm_obj, arg_ptr, arg_len);

  params = {
    method: method,
  };
  if (body.length != 0) {
    params.body = body;
  }

  callOnResponse(fetch(url, params), null, callback, arg);
}

function callWasmTarget(elem, wasm_target) {
    console.log("calling", wasm_target);
    current_node = elem;
    wasm_obj.instance.exports[wasm_target]()
}

function handleWsrGetters() {
  const elems = document.querySelectorAll("[wsr-get]");

  for (const elem of elems) {
    const url = elem.getAttribute("wsr-get");
    const wasm_target = elem.getAttribute("wsr-generate");
    callOnResponse(fetch(url), elem, wasm_target);
  }
}


function getWsrArgument(elem) {
  const arg_attr = elem.getAttribute("wsr-argument-attribute");

  if (arg_attr !== null) {
    return elem.getAttribute(arg_attr);
  }

  const arg_prop = elem.getAttribute("wsr-argument-property");
  if (arg_prop != null) {
    return elem[arg_prop];
  }

  const arg_direct = elem.getAttribute("wsr-argument-direct");
  if (arg_direct != null) {
    return arg_direct;
  }
  return null;
}
function bindWsrEvent(elem) {
  const event = elem.getAttribute("wsr-onevent");
  const wasm_target = elem.getAttribute("wsr-generate");
  elem.addEventListener(event, () => {
    const argument = getWsrArgument(elem);
    if (argument != null) {
      const encoder = new TextEncoder();
      const encoded = encoder.encode(argument);

      wasm_obj.instance.exports.allocateInputBuffer(encoded.byteLength);
      const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
      const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, encoded.byteLength);
      input_buffer.set(encoded);
    }

    callWasmTarget(elem, wasm_target);
  });
}

// FIXME dedup with getters
function handleWsrOnEvent() {
  const elems = document.querySelectorAll("[wsr-onevent]");

  for (const elem of elems) {
    bindWsrEvent(elem);
  }
}

function doWsrImmediate(elem) {
  const wasm_target = elem.getAttribute("wsr-immediate");

  const encoder = new TextEncoder();
  const encoded = encoder.encode(getWsrArgument(elem));

  wasm_obj.instance.exports.allocateInputBuffer(encoded.byteLength);
  const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
  const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, encoded.byteLength);
  input_buffer.set(encoded);

  callWasmTarget(elem, wasm_target);

}

function handleWsrImmediate() {
  const elems = document.querySelectorAll("[wsr-immediate]");

  for (const elem of elems) {
    doWsrImmediate(elem);
  }
}

function handleMutation(records) {
  for (const record of records) {
    for (const elem of record.addedNodes) {
      if (elem.getAttribute("wsr-immediate") !== null) {
        doWsrImmediate(elem);
      } else if (elem.getAttribute("wsr-onevent") !== null) {
        bindWsrEvent(elem);
      } else if (elem.getAttribute("wsr-get") !== null) {
        throw new Error("Unimplemented");
      }
    }
  }
}


async function init() {
  const observerOptions = {
    childList: true,
    subtree: true,
  };

  const observer = new MutationObserver(handleMutation);
  observer.observe(document.body, observerOptions);

  importObj = {
    env: {
      print: print,
      replaceElemContent: replaceElemContent,
      replaceSelfContent: replaceSelfContent,
      deleteElemByQuery: deleteElemByQuery,
      getSelfProperty: getSelfProperty,
      getSelfAttribute: getSelfAttribute,
      requestFetch: requestFetch,
    },
  };

  wasm_obj = await WebAssembly.instantiateStreaming(
    fetch(wasm_url),
    importObj,
  );

  handleWsrGetters();
  handleWsrOnEvent(wasm_obj);
  handleWsrImmediate(wasm_obj);
}


window.addEventListener("load", init);
