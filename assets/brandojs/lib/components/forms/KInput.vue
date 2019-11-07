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
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"
        class="form-control form-control-danger"
        type="text">
      <p
        v-if="maxlength"
        class="maxLength">
        {{ maxlength - innerValue.length }}
      </p>
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
