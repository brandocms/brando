module.exports = {
  root: true,
  env: {
    node: true,
    'cypress/globals': true
  },
  plugins: [
    'cypress'
  ],
  'extends': [
    'plugin:vue/recommended',
    '@vue/standard'
  ],
  rules: {
    'no-console': process.env.NODE_ENV === 'production' ? 'error' : 'off',
    'no-debugger': process.env.NODE_ENV === 'production' ? 'error' : 'off',
    'vue/no-v-html': 0,
    'vue/html-end-tags': 1,
    'vue/html-self-closing': 0,
    'vue/html-closing-bracket-newline': ['error', {
      'singleline': 'never',
      'multiline': 'never'
    }]
  },
  parserOptions: {
    parser: 'babel-eslint'
  }
}
