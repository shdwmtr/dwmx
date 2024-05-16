import json from '@rollup/plugin-json';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import typescript from 'rollup-plugin-typescript2';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import { defineConfig } from 'rollup';
import plugin_ from "./plugin.json"

// wrap the callServerMethod to auto input the plugin name
async function csm(m, _kw) {
	const res = await Millennium.callServerMethod(pluginName, m, _kw)
	return res
}

// add the plugin to the global map
function globalize() {
	Object.assign(window.PLUGIN_LIST[pluginName], millennium_main)
	millennium_main["default"]();
	MILLENNIUM_BACKEND_IPC.postMessage(1, { pluginName: pluginName })
}

function bootstrap() {
	!window.PLUGIN_LIST && (window.PLUGIN_LIST = {})

	if (!window.PLUGIN_LIST[pluginName]) {
		window.PLUGIN_LIST[pluginName] = {};
	}
}

function addPluginMain() 
{
  const cat = (parts) => { return parts.join('\n'); }
  return {
    name: 'add-plugin-main',
    generateBundle(_, bundle) {
      for (const fileName in bundle) {
        if (bundle[fileName].type != 'chunk') continue 

        bundle[fileName].code = cat([
          `const pluginName = "${plugin_["name"]}";`,
          bootstrap.toString(), bootstrap.name + "()",
          csm.toString(), bundle[fileName].code,
          globalize.toString(), globalize.name + "()"
        ])
      }
    }
  };
}

export default defineConfig({
	input: './frontend/index.tsx',
	plugins: [
		typescript({
			exclude: [ "*millennium.ts" ]
		}),
		addPluginMain(),
		nodeResolve(),
		commonjs(),
		json(),
		replace({
			preventAssignment: true,
			// hook call method to add plugin name
			'Millennium.callServerMethod': `csm`,
			delimiters: ['', ''],
			'm_private_context': 'window.PLUGIN_LIST[pluginName]',
		}),
	],
	context: 'window',
	external: ["react", "react-dom"],
	output: {
		name: "millennium_main",
		file: "dist/index.js",
		globals: {
			react: "window.SP_REACT",
			"react-dom": "window.SP_REACTDOM"
		},
		exports: 'named',
		format: 'iife',
	},
})