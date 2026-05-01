import js from "@eslint/js";
import globals from "globals";

export default [
	{
		ignores: ["eslint.config.mjs"],
	},
	js.configs.recommended,
	{
		languageOptions: {
			ecmaVersion: 2021,
			sourceType: "module",
			parserOptions: {
				ecmaFeatures: {
					jsx: true,
				},
			},
			globals: {
				...globals.browser,
			},
		},
	},
];
