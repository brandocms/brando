module.exports = {
  root: true,
  env: {
    node: true,
    'cypress/globals': true
  },
  plugins: [
    'cypress'
  ],
  extends: [
    'standard'
  ],
  rules: {
    'no-console': process.env.NODE_ENV === 'production' ? 'error' : 'off',
    'no-debugger': process.env.NODE_ENV === 'production' ? 'error' : 'off'
  },
  parserOptions: {
    parser: 'babel-eslint'
  }
}
