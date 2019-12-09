<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :maxlength="maxlength"
    :helpText="helpText"
    :value="value">
    <template v-slot>
      <textarea
        ref="input"
        :id="id"
        :rows="rows"
        :class="{ monospace }"
        v-model="innerValue"
        :placeholder="placeholder"
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"></textarea>
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
  }
}
</script>
<style lang="postcss" scoped>
  textarea {
    @fontsize lg;
    padding-top: 12px;
    padding-bottom: 5px;
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
