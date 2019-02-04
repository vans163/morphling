function morphling_rpc_set_cookie(session_token) {
    document.cookie = `session_token=${session_token}; Max-Age=${session_token.split(".")[2]};`;
}
function morphling_rpc_navigate(path) {
    if (location.pathname != path) {
        history.pushState(undefined, undefined, path);
    }
}


window.onpopstate = function(event) {
    morphling_ws_send("morphling_event", {action: "navigate", path: location.pathname});
};

async function n(path, args_obj = {}) {
    morphling_ws_send("morphling_event", {action: "navigate", path: path, args: args_obj});
    return false;
}

async function m(action, args_obj = {}) {
    morphling_ws_send("morphling_event", {action: action, args: args_obj});
    return false;
}

async function morphling_ws_send(method, args_obj = {}) {
    json = JSON.stringify(Object.assign({method: method}, args_obj))
    window.morphling_ws.send(json)
}

function morphling_apply_dom_diff(old_dom, dom_diff) {
    var new_dom = dom_diff.reduce(function(acc, v) {
        if (v.t == "eq") {
            return acc + old_dom.substring(v.op, v.op+v.s);
        } else if (v.t == "ins") {
            return acc + v.b;
        }
    }, "")
    return new_dom;
}

window.morphling_log = false;
window.morphling_cur_dom = "";
async function morphling_ws_proc(data) {
    json = JSON.parse(data);
    switch(json.method) {
        case "morphling_dom_diff":
            var t0=performance.now();

            old_dom = window.morphling_cur_dom;
            dom_diff = json.payload;
            new_dom = morphling_apply_dom_diff(old_dom, dom_diff);
            window.morphling_cur_dom = new_dom;

            morphdom(document.documentElement, new_dom, {
                onNodeAdded: (node)=> {
                    if (node.nodeType == 1) { 
                        var att = node.getAttribute('morph-script');
                        if (att != null) {
                            node.innerHTML = eval(att);
                        }
                    }
                },
                onBeforeElUpdated: (oldEl, newEl) => {
                    if (newEl.nodeType == 1) {
                        var att = newEl.getAttribute('morph-script');
                        if (att != null) {
                            newEl.innerHTML = eval(att);
                        }
                    }
                }
            });
            var t1=performance.now();
            if (window.morphling_log == true) {
                console.log('morph took', t1-t0);
            }
            return;

        case "morphling_rpc":
            try {
                window[json.rpc_method](json.payload);
            } catch (err) {
                console.log("morphling_rpc_error", err);
            }
            return;

        case "morphling_eval":
            try {
                eval(json.payload);
            } catch (err) {
                console.log("morphling_eval_error", err);
            }
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