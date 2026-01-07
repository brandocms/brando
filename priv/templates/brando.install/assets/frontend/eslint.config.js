import unusedImports from 'eslint-plugin-unused-imports'

export default [
  {
    plugins: { 'unused-imports': unusedImports },
    rules: {
      // turn off generic rule…
      'no-unused-vars': 'off',
      // …and use the specialised ones
      'unused-imports/no-unused-imports': 'error',
      'unused-imports/no-unused-vars': [
        'warn',
        {
          vars: 'all',
          args: 'after-used',
          varsIgnorePattern: '^_',
          argsIgnorePattern: '^_',
        },
      ],
    },
  },
]
