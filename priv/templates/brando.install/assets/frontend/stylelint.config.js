module.exports = {
  extends: 'stylelint-config-recommended',
  rules: {
    indentation: 2,
    'color-no-invalid-hex': true,
    'font-family-no-duplicate-names': true,
    'font-family-no-missing-generic-family-keyword': true,
    'declaration-block-no-shorthand-property-overrides': true,
    'declaration-block-no-duplicate-properties': true,
    'unit-no-unknown': true,
    'property-no-unknown': true,
    'block-no-empty': true,
    'selector-pseudo-class-no-unknown': true,
    'selector-pseudo-element-no-unknown': true,
    'selector-type-no-unknown': true,
    'no-duplicate-selectors': true,
    'at-rule-no-unknown': [true, {
      ignoreAtRules: [
        'column',
        'column-offset',
        'column-typography',
        'container',
        'embed-responsive',
        'europa',
        'extend',
        'fontsize',
        'iterate',
        'responsive',
        'rfs',
        'row',
        'space',
        'space!',
        'unpack'
      ]
    }],
    'no-descending-specificity': null
  }
}
