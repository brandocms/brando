<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :maxlength="maxlength"
    :help-text="helpText"
    :value="value">
    <template #default>
      <input
        :id="id"
        ref="input"
        v-model="innerValue"
        :class="{ monospace }"
        :placeholder="placeholder"
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"
        type="text">
    </template>
  </KFieldBase>
</template>

<script>

import slugify from 'slugify'

export default {
  props: {
    disabled: {
      type: Boolean,
      default: false
    },

    from: {
      type: [String],
      default: null
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: true
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

  watch: {
    from (value) {
      this.innerValue = slugify(this.from, { lower: true, strict: true })
    }
  },

  created () {
    this.innerValue = this.value
  }
}
</script>
<style lang="postcss" scoped>
  input {
    @fontsize base;
    font-family: theme(typography.families.mono);
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
</style>
