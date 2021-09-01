<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :maxlength="maxlength"
    :character-count="characterCount"
    :help-text="helpText"
    :compact="compact"
    :value="value">
    <template #default>
      <input
        :id="id"
        ref="input"
        :value="innerValue"
        :class="{ monospace, invert }"
        :placeholder="placeholder"
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"
        type="text"
        @input="handleInput">
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

    compact: {
      type: Boolean,
      default: false
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: false,
      default: null
    },

    maxlength: {
      type: Number,
      default: null
    },

    characterCount: {
      type: Boolean,
      default: false,
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

    monospace: {
      type: Boolean,
      default: false
    },

    invert: {
      type: Boolean,
      default: false
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
    }
  },

  watch: {
    value (v) {
      this.innerValue = v
    }
  },

  created () {
    if (this.value) {
      this.innerValue = this.value
    }
  },

  methods: {
    focus () {
      this.$refs.input.focus()
    },

    /**
     * this garbage is here mostly to deal with KInputs inside modals in Villain blocks. :(
     */
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
  input {
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

      &::placeholder {
        @fontsize base(0.8);
        font-family: theme(typography.families.mono);
      }
    }

    &.invert {
      @color fg input;
      @color bg dark;
    }
  }
</style>
