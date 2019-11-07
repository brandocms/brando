module.exports = {
  parser: 'vue-eslint-parser',
  parserOptions: {
    parser: 'babel-eslint',
    sourceType: 'module'
  },
  env: {
    browser: true,
  },
  // https://github.com/feross/standard/blob/master/RULES.md#javascript-standard-style
  extends: [
    'plugin:vue/recommended',
    '@vue/standard'
  ],
  // required to lint *.vue files
  plugins: [
    'vue'
  ],
  settings: {
    'html/html-extensions': [".html"]  // don't include .vue
  },
  // add your custom rules here
  rules: {
    // allow paren-less arrow functions
    'arrow-parens': 0,
    // allow async-await
    'generator-star-spacing': 0,
    // vuejs screws up this anyways
    'no-use-before-define': 0,
    // allow debugger during development
    'standard/no-callback-literal': 0,
    'no-debugger': process.env.NODE_ENV === 'production' ? 2 : 0,
    "vue/no-v-html": 0,
    "vue/html-end-tags": 1,
    "vue/html-self-closing": 0,
    "vue/html-closing-bracket-newline": ["error", {
      "singleline": "never",
      "multiline": "never"
    }],
    "vue/max-attributes-per-line": ["error", {
      "singleline": 1,
      "multiline": {
        "max": 1,
        "allowFirstLine": false
      }
    }]
  }
}
