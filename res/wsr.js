const wasm_url = document.currentScript.getAttribute("wasm-url");
/** @type WebAssembly.WebAssemblyInstantiatedSource */
let wasm_obj = null;

let current_node = null;
let current_event = null;
let last_error = null;

function print(ptr, len) {
  if (wasm_obj === null) return;
  const arr = new Uint8Array(wasm_obj.instance.exports.memory.buffer, ptr, len);
  const decoder = new TextDecoder();
  const s = decoder.decode(arr);
  console.log(s);
}

function captureBacktrace(idx) {
  last_error.set(idx, new Error().stack);
}

function printCapturedBacktrace(idx) {
  console.log(last_error.get(idx));
}

function getWasmString(ptr, len) {
  if (len == 0) return "";
  const output_buf = new Uint8Array(wasm_obj.instance.exports.memory.buffer, ptr, len);
  const decoder = new TextDecoder();
  return decoder.decode(output_buf);
}

function replaceSelfProperty(
  content_ptr, content_len,
  property_ptr, property_len,
) {
  const content = getWasmString(content_ptr, content_len);
  const property = getWasmString(property_ptr, property_len);

  current_node[property] = content;
}

function replaceElemProperty(
  elem_id_ptr, elem_id_len,
  content_ptr, content_len,
  property_ptr, property_len,
) {
  const elem_id = getWasmString(elem_id_ptr, elem_id_len);
  const content = getWasmString(content_ptr, content_len);
  const property = getWasmString(property_ptr, property_len);

  const node = document.getElementById(elem_id);
  node[property] = content;
}

function getElemProperty(
  elem_id_ptr, elem_id_len,
  property_ptr, property_len,
) {
  const elem_id = getWasmString(elem_id_ptr, elem_id_len);
  const property = getWasmString(property_ptr, property_len);

  const node = document.getElementById(elem_id);
  setWasmInputBuffer(node[property]);
}

function appendToElem(
  elem_id_ptr, elem_id_len,
  content_ptr, content_len,
) {
  const elem_id = getWasmString(elem_id_ptr, elem_id_len);
  const content = getWasmString(content_ptr, content_len);

  const node = document.getElementById(elem_id);
  node.innerHTML += content;
}

function setWasmInputBuffer(s) {
  console.log(s);
  const encoder = new TextEncoder();
  const data = encoder.encode(s);

  wasm_obj.instance.exports.allocateInputBuffer(data.length);
  const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
  const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, data.length);
  input_buffer.set(data);

}

function getSelfProperty(property_ptr, property_len) {
  const prop = getWasmString(property_ptr, property_len);
  setWasmInputBuffer(current_node[prop]);
}

function getEventProperty(property_ptr, property_len) {
  const prop = getWasmString(property_ptr, property_len);
  console.log(current_event, prop);
  setWasmInputBuffer(current_event[prop]);
}

function getSelfAttribute(property_ptr, property_len) {
  //FIXME: Wrong name
  const prop = getWasmString(property_ptr, property_len);
  setWasmInputBuffer(current_node.getAttribute(prop));
}

function callOnResponse(fetch_promise, elem, wasm_target) {
  fetch_promise.then((response) => response.bytes()).then((body) => {
    wasm_obj.instance.exports.allocateInputBuffer(body.length);
    const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();

    if (body.length > 0) {
      const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, body.length);
      input_buffer.set(body);
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
) {
  const url = getWasmString(url_ptr, url_len);
  const body = getWasmString(body_ptr, body_len);
  const method = getWasmString(method_ptr, method_len);
  const callback = getWasmString(callback_ptr, callback_len);

  params = {
    method: method,
  };
  if (body.length != 0) {
    params.body = body;
  }

  callOnResponse(fetch(url, params), current_node, callback);
}

function callWasmTarget(elem, wasm_target) {
  current_node = elem;
  last_error = new Map();

  try {
    wasm_obj.instance.exports[wasm_target]()
  } catch (error) {
    console.error(wasm_target, error);
  }
}

function handleWsrGetters() {
  {
    const elems = document.querySelectorAll("[wsr-get]");

    for (const elem of elems) {
      const url = elem.getAttribute("wsr-get");
      const wasm_target = elem.getAttribute("wsr-generate");
      callOnResponse(fetch(url), elem, wasm_target);
    }
  }

  {
    const elems = document.querySelectorAll("[wsr-get-1]");
    for (const elem of elems) {
      let i = 1;
      while (true) {
        const url = elem.getAttribute(`wsr-get-${i}`);
        if (url == null) break;
        const wasm_target = elem.getAttribute(`wsr-generate-${i}`);
        callOnResponse(fetch(url), elem, wasm_target);
        i += 1;
      }
    }
  }
}


function bindWsrEvent(elem) {
  const event = elem.getAttribute("wsr-onevent");
  const wasm_target = elem.getAttribute("wsr-generate");
  elem.addEventListener(event, (ev) => {
    current_event = ev;
    callWasmTarget(elem, wasm_target);
    current_event = null;
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
  callWasmTarget(elem, wasm_target);
}

function handleWsrImmediate() {
  const elems = document.querySelectorAll("[wsr-immediate]");

  for (const elem of elems) {
    doWsrImmediate(elem);
  }
}

function handleNewNodeWsr(elem) {
  if (elem.getAttribute("wsr-immediate") !== null) {
    doWsrImmediate(elem);
  } else if (elem.getAttribute("wsr-onevent") !== null) {
    bindWsrEvent(elem);
  } else if (elem.getAttribute("wsr-get") !== null) {
    throw new Error("Unimplemented");
  }

  for (const child of elem.children) {
    handleNewNodeWsr(child);
  }
}

function handleMutation(records) {
  for (const record of records) {
    for (const elem of record.addedNodes) {
      handleNewNodeWsr(elem);
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
      captureBacktrace: captureBacktrace,
      printCapturedBacktrace: printCapturedBacktrace,
      replaceElemProperty: replaceElemProperty,
      replaceSelfProperty: replaceSelfProperty,
      getSelfProperty: getSelfProperty,
      getSelfAttribute: getSelfAttribute,
      getElemProperty: getElemProperty,
      appendToElem: appendToElem,
      getEventProperty: getEventProperty,
      requestFetch: requestFetch,
    },
  };

  wasm_obj = await WebAssembly.instantiateStreaming(
    fetch(wasm_url),
    importObj,
  );

  handleWsrGetters();
  handleWsrOnEvent();
  handleWsrImmediate();
}


window.addEventListener("load", init);
