import { callable, ConfirmModal, pluginSelf, showModal } from '@steambrew/client';

type OriginalOpenFunction = (url?: string, target?: string, features?: string, replace?: boolean) => Window | null;
const originalOpen: OriginalOpenFunction = window.open;

const PatchAllWindows = callable<[]>('PatchAllWindows');

// The native window doesn't exist yet when window.open is called, so patching
// right before it misses the new window. Try a few times after it opens instead.
const PatchWindowsSoon = (delays: number[]) => {
	for (const ms of delays) {
		setTimeout(() => PatchAllWindows(), ms);
	}
};

const Patches = {
	TARGET_WINDOW_FLAG: [4114, 2],
	NEW_WINDOW_FLAG: 274,
};

window.open = function (url?: string, target?: string, features?: string, replace?: boolean): Window | null {
	if (!url) {
		return originalOpen(url, target, features, replace);
	}

	const parsedUrl = new URL(url);
	const queryParams = parsedUrl.searchParams;

	const windowFeature = 'createflags';

	if (queryParams.has(windowFeature) && Patches.TARGET_WINDOW_FLAG.includes(parseInt(queryParams.get(windowFeature) || ''))) {
		queryParams.set(windowFeature, Patches.NEW_WINDOW_FLAG.toString());
		parsedUrl.search = queryParams.toString();
		url = parsedUrl.toString();
	}

	const newWindow = originalOpen(url, target, features, replace);
	PatchWindowsSoon([0, 100, 500, 1500]);
	return newWindow;
};

const ShowAlertMessage = (strTitle: string, strMessage: string) => showModal(<ConfirmModal strTitle={strTitle} strDescription={strMessage} />);

export default async function PluginMain() {
	pluginSelf.ShowAlertMessage = ShowAlertMessage;

	// The main Steam window is usually already open by the time the plugin loads.
	PatchWindowsSoon([500, 2000, 5000]);
}
