import js from "@eslint/js";
import globals from "globals";

export default [
	{
		ignores: ["eslint.config.mjs"], // don't lint the config file itself
	},
	js.configs.recommended,
	{
		languageOptions: {
			ecmaVersion: 2021,
			sourceType: "module",
			globals: {
				...globals.browser,
			},
		},
	},
];
