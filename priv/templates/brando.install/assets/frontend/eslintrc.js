module.exports = {
  root: true,
  env: {
    browser: true,
    'cypress/globals': true,
  },
  globals: {
    __APP_NAME__: true,
    __ENV__: true,
    __VSN_HASH__: true,
    __VERSION__: true
  },
  plugins: [
    'cypress'
  ],
  extends: [
    'airbnb-base',
    'plugin:compat/recommended'
  ],
  rules: {
    'no-console': 'off',
    'no-debugger': 'off',
    'arrow-parens': [2, 'as-needed'],
    'class-methods-use-this': 0,
    'comma-dangle': ['error', 'never'],
    'no-console': 'off',
    'no-debugger': 'off',
    'no-param-reassign': 0,
    'no-underscore-dangle': 0,
    'quotes': ['error', 'single'],
    'radix': ['error', 'as-needed'],
    'semi': 0,
    'space-before-function-paren': ['error', 'always'],
    'import/no-extraneous-dependencies': ['error', { 'devDependencies': ['./postcss.config.js', './webpack.*.js'] }]
  },
  parserOptions: {
    parser: 'babel-eslint'
  }
}
