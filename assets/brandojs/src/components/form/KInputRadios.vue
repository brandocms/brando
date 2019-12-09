<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :helpText="helpText"
    :value="value">
    <template v-slot>
      <div class="radios-wrapper">
        <div
          v-for="o in options"
          :key="o.value"
          class="form-check">
          <label class="form-check-label">
            <input
              v-model="innerValue"
              :name="name"
              :value="o.value"
              class="form-check-input"
              type="radio">
            <span class="label-text">{{ o.name }}</span>
          </label>
        </div>
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

  // mounted () {
  //   gsap.set(this.$refs.input, { width: 0 })
  //   gsap.to(this.$refs.input, { ease: 'sine.easeOut', width: '100%' })
  // },

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
    }

    label {
      display: flex;

      span {
        margin-top: -1px;
      }
    }
  }
</style>
