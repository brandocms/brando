<template>
  <ValidationProvider
    v-slot="{ errors, invalid }"
    :name="name"
    :immediate="true"
    :rules="rules">
    <div :class="{'form-group': true, 'has-danger': invalid }">
      <div class="label-wrapper">
        <label
          :for="id"
          class="control-label">
          {{ label }}
        </label>
        <span v-if="invalid">
          <i class="fa fa-exclamation-circle text-danger" />
          {{ errors[0] }}
        </span>
      </div>

      <Multiselect
        v-model="innerValue"
        :options="options"
        :track-by="optionValueKey"
        :label="optionLabelKey"
        :show-labels="showLabels"
        :placeholder="placeholder"
        :multiple="multiple" />
    </div>
  </ValidationProvider>
</template>

<script>
export default {
  props: {
    rules: {
      type: String,
      default: null
    },

    optionValueKey: {
      type: String,
      required: true,
      default: 'value'
    },

    optionLabelKey: {
      type: String,
      required: true,
      default: 'name'
    },

    placeholder: {
      type: String,
      default: 'Velg en eller flere'
    },

    multiple: {
      type: Boolean,
      default: true
    },

    showLabels: {
      type: Boolean,
      default: false
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

    value: {
      required: false,
      default: '',
      type: null
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
    innerValue (value) {
      this.$emit('input', value)
    },

    value (value) {
      this.innerValue = value
    }
  },

  created () {
    this.innerValue = this.value
  }
}
</script>
