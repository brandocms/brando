<template>
  <KFieldBase
    :name="name"
    :rules="rules"
    :help-text="helpText"
    :label="label"
    :compact="compact"
    :value="value">
    <template #default>
      <div class="check-wrapper">
        <div
          class="form-check">
          <label class="form-check-label">
            <div
              :class="classBindings"
              @click="toggle">
              <div class="toggle-indicator"></div>
            </div>
            <input
              v-model="innerValue"
              :name="name"
              class="form-check-input"
              type="hidden">
          </label>
        </div>
      </div>
    </template>
  </KFieldBase>
</template>

<script>
export default {
  props: {
    compact: {
      type: Boolean,
      default: false
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
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
    },

    classBindings () {
      return {
        toggle: true,
        active: this.innerValue
      }
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
  },

  methods: {
    toggle () {
      this.innerValue = !this.innerValue
    }
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
      margin-top: 4px;
    }

    label {
      display: flex;

      /* span {
        margin-top: -1px;
      } */
    }
  }

  .toggle {
    width: calc(25px * 2);
    padding: 5px;

    background: #aaa;
    border-radius: 25px;
    transition: background-color 500ms ease-out;

    &.active {
      background-color: #4BB543;
      .toggle-indicator {
        transform: translateX(20px);
      }
    }

    &-indicator {
      width: 20px;
      height: 20px;
      background-color: #ffffff;
      border-radius: 20px;
      transition: transform 100ms ease-out;
    }
  }
</style>
