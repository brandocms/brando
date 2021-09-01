<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :character-count="characterCount"
    :maxlength="maxlength"
    :help-text="helpText"
    :value="value">
    <template #default>
      <textarea
        :id="id"
        ref="input"
        :value="innerValue"
        :rows="rows"
        :class="{ monospace }"
        :placeholder="placeholder"
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"
        @input="handleInput"></textarea>
    </template>
  </KFieldBase>
</template>

<script>

export default {
  props: {
    disabled: {
      type: Boolean,
      default: false
    },

    characterCount: {
      type: Boolean,
      default: false
    },

    helpText: {
      type: String,
      default: null
    },

    rows: {
      type: Number,
      default: 3
    },

    label: {
      type: String,
      required: true
    },

    maxlength: {
      type: Number,
      default: null
    },

    monospace: {
      type: Boolean,
      default: false
    },

    placeholder: {
      type: String,
      required: false,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    name: {
      type: String,
      required: true
    },

    value: {
      type: [String, Number],
      default: ''
    }
  },

  data () {
    return {
      innerValue: ''
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    charCounter () {
      return this.innerValue.length
    }
  },

  created () {
    if (this.value) {
      this.innerValue = this.value
    }
  },

  methods: {
    handleInput (event) {
      const val = event.target.value
      const pos = event.target.selectionStart
      if (val !== this.value) {
        this.$nextTick(() => (event.target.selectionEnd = pos))
      }
      this.innerValue = val
      this.$emit('input', this.innerValue)
    }
  }
}
</script>
<style lang="postcss" scoped>
  textarea {
    @fontsize base;
    padding-top: 12px;
    padding-bottom: 12px;
    padding-left: 15px;
    padding-right: 15px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;

    &.monospace {
      @fontsize base(0.8);
      font-family: theme(typography.families.mono);
      padding-bottom: 12px;
      padding-top: 16px;
    }
  }

  .counter {
    font-size: 12px;
    float: right;
  }
</style>
