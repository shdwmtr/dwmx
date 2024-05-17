type OriginalOpenFunction = (url?: string, target?: string, features?: string, replace?: boolean) => Window | null;
const originalOpen: OriginalOpenFunction = window.open;

window.open = function(url?: string, target?: string, features?: string, replace?: boolean): Window | null {

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

export default async function PluginMain() { }