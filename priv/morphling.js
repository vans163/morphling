async function m(action, args_obj = {}) {
    morphling_ws_send("morphling_event", {action: action, args: args_obj})
}

async function morphling_ws_send(method, args_obj = {}) {
    json = JSON.stringify(Object.assign({method: method}, args_obj))
    window.morphling_ws.send(json)
}

async function morphling_ws_proc(data) {
    json = JSON.parse(data);
    switch(json.method) {
        case "morphling_dom_diff":
            morphdom(document.documentElement, json.payload);
            return;
        case "morphling_rpc":
            try {
                window[json.rpc_method](json.payload);
            } catch (err) {}
            return;
    }
}

window.morphling_ws = undefined;
window.morphling_ws_url = undefined;
async function morphling_ws_connect() {
    window.morphling_ws = new WebSocket(window.morphling_ws_url);
    window.morphling_ws.onmessage = event=> morphling_ws_proc(event.data);
    const wait_onopen = () => new Promise(resolve=> window.morphling_ws.addEventListener('open', resolve, { once: true }));
    var res = await wait_onopen();
    console.log("Morphling connected!");
}
async function morphling_ws_process() {
    var ws = window.morphling_ws;
    if (window.navigator.onLine == false) {
        setTimeout(morphling_ws_process, 3000); return;
    }
    if (ws !== undefined && (ws.readyState === WebSocket.OPEN || ws.readyState == WebSocket.CONNECTING || ws.readyState == WebSocket.CLOSING)) {
        setTimeout(morphling_ws_process, 3000); return;
    }

    morphling_ws_connect();
    setTimeout(morphling_ws_process, 3000); return;
}

function Morphling(ws_url) {
    window.morphling_ws_url = ws_url;
    morphling_ws_process();
}
