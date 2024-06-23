const pluginName = "dwmx";
function InitializePlugins() {
    /**
     * This function is called n times depending on n plugin count,
     * Create the plugin list if it wasn't already created
     */
    !window.PLUGIN_LIST && (window.PLUGIN_LIST = {});
    // initialize a container for the plugin
    if (!window.PLUGIN_LIST[pluginName]) {
        window.PLUGIN_LIST[pluginName] = {};
    }
}
InitializePlugins()
async function wrappedCallServerMethod(methodName, kwargs) {
    // @ts-ignore
    return await Millennium.callServerMethod(pluginName, methodName, kwargs);
}
var millennium_main = (function (exports) {
    'use strict';

    const IPCMain = {
        postMessage: (messageId, contents) => {
            return new Promise((resolve) => {
                const message = { id: messageId, iteration: window.CURRENT_IPC_CALL_COUNT++, data: contents };
                const messageHandler = function (data) {
                    const json = JSON.parse(data.data);
                    /**
                     * wait to receive the correct message id from the backend
                     */
                    if (json.id != message.iteration)
                        return;
                    resolve(json);
                    window.MILLENNIUM_IPC_SOCKET.removeEventListener('message', messageHandler);
                };
                window.MILLENNIUM_IPC_SOCKET.addEventListener('message', messageHandler);
                window.MILLENNIUM_IPC_SOCKET.send(JSON.stringify(message));
            });
        }
    };
    window.MILLENNIUM_BACKEND_IPC = IPCMain;
    window.Millennium = {
        // @ts-ignore (ignore overloaded function)
        callServerMethod: (pluginName, methodName, kwargs) => {
            return new Promise((resolve, reject) => {
                const query = {
                    pluginName: pluginName,
                    methodName: methodName
                };
                if (kwargs)
                    query.argumentList = kwargs;
                /* call handled from "src\core\ipc\pipe.cpp @ L:67" */
                window.MILLENNIUM_BACKEND_IPC.postMessage(0, query).then((response) => {
                    if (response?.failedRequest) {
                        const m = ` wrappedCallServerMethod() from [name: ${pluginName}, method: ${methodName}] failed on exception -> ${response.failMessage}`;
                        // Millennium can't accurately pin point where this came from
                        // check the sources tab and find your plugins index.js, and look for a call that could error this
                        throw new Error(m);
                    }
                    const val = response.returnValue;
                    if (typeof val === 'string') {
                        resolve(atob(val));
                    }
                    resolve(val);
                });
            });
        },
        AddWindowCreateHook: (callback) => {
            // used to have extended functionality but removed since it was shotty
            g_PopupManager.AddPopupCreatedCallback((e) => {
                callback(e);
            });
        },
        findElement: (privateDocument, querySelector, timeout) => {
            return new Promise((resolve, reject) => {
                const matchedElements = privateDocument.querySelectorAll(querySelector);
                /**
                 * node is already in DOM and doesn't require watchdog
                 */
                if (matchedElements.length) {
                    resolve(matchedElements);
                }
                let timer = null;
                const observer = new MutationObserver(() => {
                    const matchedElements = privateDocument.querySelectorAll(querySelector);
                    if (matchedElements.length) {
                        if (timer)
                            clearTimeout(timer);
                        observer.disconnect();
                        resolve(matchedElements);
                    }
                });
                /** observe the document body for item changes, assuming we are waiting for target element */
                observer.observe(privateDocument.body, {
                    childList: true,
                    subtree: true
                });
                if (timeout) {
                    timer = setTimeout(() => {
                        observer.disconnect();
                        reject();
                    }, timeout);
                }
            });
        },
        exposeObj: function (obj) {
            for (const key in obj) {
                exports[key] = obj[key];
            }
        }
    };
    /**
     * @brief
     * pluginSelf is a sandbox for data specific to your plugin.
     * You can't access other plugins sandboxes and they can't access yours
     *
     * @example
     * | pluginSelf.var = "Hello"
     * | console.log(pluginSelf.var) -> Hello
     */
    window.PLUGIN_LIST[pluginName];
    const Millennium = window.Millennium;

    const originalOpen = window.open;
    window.open = function (url, target, features, replace) {
        if (!url) {
            return originalOpen(url, target, features, replace);
        }
        const parsedUrl = new URL(url);
        const queryParams = parsedUrl.searchParams;
        if (queryParams.has('createflags')
            && queryParams.get('createflags') === '18') {
            queryParams.set('createflags', '274');
            parsedUrl.search = queryParams.toString();
            url = parsedUrl.toString();
        }
        console.log("open", url);
        return originalOpen(url, target, features, replace);
    };
    async function PluginMain() {
        console.log("loading dwmx");
        Millennium.exposeObj({});
    }

    exports.default = PluginMain;

    Object.defineProperty(exports, '__esModule', { value: true });

    return exports;

})({});

function ExecutePluginModule() {
    // Assign the plugin on plugin list. 
    Object.assign(window.PLUGIN_LIST[pluginName], millennium_main);
    // Run the rolled up plugins default exported function 
    millennium_main["default"]();
    MILLENNIUM_BACKEND_IPC.postMessage(1, { pluginName: pluginName });
}
ExecutePluginModule()