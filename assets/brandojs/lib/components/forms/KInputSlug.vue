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
        :name="name"
        placeholder="url"
        class="form-control form-control-danger text-mono"
        type="text">
    </div>
  </ValidationProvider>
</template>

<script>
import slug from 'url-slug'

export default {
  props: {
    rules: {
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
      default: ''
    },

    name: {
      type: String,
      required: true
    },

    type: {
      type: String,
      required: false,
      default: ''
    },

    from: {
      required: true,
      type: String
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

    from (value) {
      this.innerValue = slug(value)
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
