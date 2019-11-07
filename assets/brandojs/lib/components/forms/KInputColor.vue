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

      <input
        :id="id"
        v-model="innerValue"
        :placeholder="placeholder"
        :name="name"

        class="form-control form-control-danger"
        type="color">
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
    rules: {
      type: String,
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

    placeholder: {
      type: String,
      required: false,
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
