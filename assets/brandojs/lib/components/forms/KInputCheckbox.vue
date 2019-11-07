<template>
  <ValidationProvider
    v-slot="{ errors, invalid }"
    :name="name"
    :immediate="true"
    :rules="rules">
    <div :class="{'form-group': true, 'has-danger': invalid }">
      <div class="form-check">
        <div class="label-wrapper">
          <label class="form-check-label">
            <input
              v-model="innerValue"
              :name="name"
              class="form-check-input"
              type="checkbox">
            {{ label }}
          </label>
        </div>
        <span v-if="invalid">
          <i class="fa fa-exclamation-circle text-danger" />
          {{ errors[0] }}
        </span>
      </div>
      <p
        v-if="helpText"
        class="help-text">
        <i class="fa fa-fw fa-arrow-alt-circle-up mr-1" />
        <span v-html="helpText" />
      </p>
    </div>
  </ValidationProvider>
</template>

<script>
export default {
  props: {
    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
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
      type: [String, Number, Boolean],
      required: false,
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
