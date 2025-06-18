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

function requestPut(
  url_ptr, url_len,
  body_ptr, body_len,
) {
  const url = getWasmString(wasm_obj, url_ptr, url_len);
  const body = getWasmString(wasm_obj, body_ptr, body_len);

  fetch(url, {
    method: "PUT",
    body,
  });
}

function callWasmTarget(elem, wasm_target) {
    current_node = elem;
    wasm_obj.instance.exports[wasm_target]()
}

function handleWsrGetters(wasm_obj) {
  const elems = document.querySelectorAll("[wsr-get]");

  for (const elem of elems) {
    const url = elem.getAttribute("wsr-get");
    const wasm_target = elem.getAttribute("wsr-generate");
    fetch(url).then((response) => response.bytes()).then((body) => {
      wasm_obj.instance.exports.allocateInputBuffer(body.length);
      const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
      if (body.length != 0) {
        const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, body.length);
        input_buffer.set(body);
      }

      callWasmTarget(elem, wasm_target);
    });
  }
}

// FIXME dedup with getters
function handleWsrOnEvent(wasm_obj) {
  const elems = document.querySelectorAll("[wsr-onevent]");

  for (const elem of elems) {
    const event = elem.getAttribute("wsr-onevent");
    const argument = elem.getAttribute("wsr-argument");
    const wasm_target = elem.getAttribute("wsr-generate");
    elem.addEventListener(event, () => {
      const encoder = new TextEncoder();
      const encoded = encoder.encode(elem[argument]);

      wasm_obj.instance.exports.allocateInputBuffer(encoded.byteLength);
      const input_buffer_ptr = wasm_obj.instance.exports.getInputBuffer();
      const input_buffer = new Uint8Array(wasm_obj.instance.exports.memory.buffer, input_buffer_ptr, encoded.byteLength);
      input_buffer.set(encoded);

      callWasmTarget(elem, wasm_target);
    });
  }
}

async function init() {
  importObj = {
    env: {
      print: print,
      replaceElemContent: replaceElemContent,
      replaceSelfContent: replaceSelfContent,
      requestPut: requestPut,
    },
  };

  wasm_obj = await WebAssembly.instantiateStreaming(
    fetch(wasm_url),
    importObj,
  );

  handleWsrGetters(wasm_obj);
  handleWsrOnEvent(wasm_obj);
}


window.addEventListener("load", init);
