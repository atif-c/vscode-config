/** @type {import('prettier').Config} */
const config = {
	arrowParens: 'avoid',
	printWidth: 100,
	proseWrap: 'always',
	singleQuote: true,
	trailingComma: 'none',
	useTabs: true,
	plugins: ['prettier-plugin-jsdoc', '@aforemendude/prettier-plugin-wrap-comments']
};

export default config;
