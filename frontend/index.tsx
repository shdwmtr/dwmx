// import { Millennium, pluginSelf } from "./millennium"; 
import React from "react";

type OriginalOpenFunction = (url?: string, target?: string, features?: string, replace?: boolean) => Window | null;

// Store the original window.open function
const originalOpen: OriginalOpenFunction = window.open;

// Define a custom function to replace window.open
window.open = function(url?: string, target?: string, features?: string, replace?: boolean): Window | null {
    // Do something before calling the original window.open
    if (url) {
        const parsedUrl = new URL(url);
        const queryParams = parsedUrl.searchParams;

        // settings, properties, friends
        if (queryParams.has('createflags') && queryParams.get('createflags') === '18') {
            queryParams.set('createflags', '274');
            parsedUrl.search = queryParams.toString();
            url = parsedUrl.toString();
        }
    }
    // Call the original window.open with the updated URL
    return originalOpen(url, target, features, replace);
};

export const renderPluginSettings: React.FC = () => {

    return (
        <>
            <div>This is an example Element</div>
        </>
    )
}

// Entry point on the front end of your plugin
export default async function PluginMain() { }