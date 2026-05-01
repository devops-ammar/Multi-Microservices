import js from "@eslint/js";
import reactPlugin from "eslint-plugin-react";
export default [
	js.configs.recommended,
	reactPlugin.configs.flat.recommended,
	{
		settings: { react: { version: "detect" } },
		languageOptions: {
			ecmaVersion: 2021,
			sourceType: "module",
		},
	},
];
