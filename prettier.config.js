/** @type {import("prettier").Config} */
const config = {
	arrowParens: 'avoid',
	printWidth: 100,
	singleQuote: true,
	trailingComma: 'none',
	useTabs: true,
	plugins: ['prettier-plugin-jsdoc', '@ianvs/prettier-plugin-sort-imports']
};

export default config;
