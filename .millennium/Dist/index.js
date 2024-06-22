const pluginName = "steam-mica";
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

    const originalOpen = window.open;
    window.open = function (url, target, features, replace) {
        if (!url) {
            return originalOpen(url, target, features, replace);
        }
        const parsedUrl = new URL(url);
        const queryParams = parsedUrl.searchParams;
        if (queryParams.has('createflags') && queryParams.get('createflags') === '18') {
            queryParams.set('createflags', '274');
            parsedUrl.search = queryParams.toString();
            url = parsedUrl.toString();
        }
        return originalOpen(url, target, features, replace);
    };
    async function PluginMain() { }

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