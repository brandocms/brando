<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :compact="compact"
    :maxlength="maxlength"
    :help-text="helpText"
    :value="value">
    <template #default>
      <div class="wrap">
        <input
          :id="id"
          ref="input"
          v-model="innerValue"
          :name="name"
          :disabled="disabled"
          type="color">
        <input
          :id="id + '_text'"
          ref="input2"
          v-model="innerValue"
          :class="{ monospace: true }"
          :placeholder="placeholder"
          :maxlength="maxlength"
          :name="name"
          :disabled="disabled"
          type="text">
      </div>
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

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: false,
      default: null
    },

    compact: {
      type: Boolean,
      default: false
    },

    maxlength: {
      type: Number,
      default: null
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
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    innerValue: {
      get () { return this.value },
      set (innerValue) { this.$emit('input', innerValue) }
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
    }
  }
}
</script>
<style lang="postcss" scoped>
  .wrap {
    display: flex;
  }

  input {
    @fontsize base;
    padding-top: 12px;
    padding-bottom: 12px;
    padding-left: 15px;
    padding-right: 15px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;
    height: 53px;

    &:first-of-type {
      width: 100px;
    }

    &.monospace {
      @fontsize base(0.8);
      font-family: theme(typography.families.mono);
      padding-bottom: 12px;
      padding-top: 16px;
    }

    &.invert {
      @color fg input;
      @color bg dark;
    }
  }
</style>
