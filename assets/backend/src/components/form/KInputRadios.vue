<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :help-text="helpText"
    :value="value">
    <template #default>
      <div
        v-if="options.length"
        class="radios-wrapper">
        <div
          v-for="o in options"
          :key="o[optionValueKey]"
          class="form-check">
          <label class="form-check-label">
            <input
              v-model="innerValue"
              :name="name"
              :value="o[optionValueKey]"
              class="form-check-input"
              type="radio">
            <span class="label-text">{{ o[optionLabelKey] }}</span>
          </label>
        </div>
      </div>
      <div v-else>
        {{ $t('no-options') }}
      </div>
    </template>
  </KFieldBase>
</template>

<script>

// import { gsap } from 'gsap'

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
      required: true
    },

    /**
     * [ { name: 'Option name', value: 1 }]
     */
    options: {
      type: Array,
      required: true
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
    },

    optionValueKey: {
      type: String,
      default: 'value'
    },

    optionLabelKey: {
      type: String,
      default: 'name'
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
  .radios-wrapper {
    margin-top: 8px;

    .form-check {
      margin-bottom: 5px;
    }

    input {
      margin-right: 17px;
      margin-top: 2px;
    }

    label {
      display: flex;
      align-items: baseline;
    }
  }
</style>
<i18n>
  {
    "en": {
      "no-options": "No available options"
    },
    "no": {
      "no-options": "Ingen tilgjengelige valg"
    }
  }
</i18n>
