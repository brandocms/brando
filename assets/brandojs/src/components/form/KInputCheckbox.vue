<template>
  <KFieldBase
    :name="name"
    :rules="rules"
    :helpText="helpText"
    :value="value">
    <template v-slot>
      <div class="check-wrapper">
        <div
          class="form-check">
          <label class="form-check-label">
            <input
              v-model="innerValue"
              :name="name"
              class="form-check-input"
              type="checkbox">
            <span class="label-text">{{ label }}</span>
          </label>
        </div>
      </div>
    </template>
  </KFieldBase>
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

<style lang="postcss" scoped>
  .check-wrapper {
    margin-top: 8px;

    .form-check {
      margin-bottom: 5px;
    }

    input {
      margin-right: 17px;
    }

    label {
      display: flex;

      span {
        margin-top: -1px;
      }
    }
  }
</style>
