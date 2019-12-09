<template>
  <div class="field-wrapper">
    <ValidationProvider
      v-slot="{ errors, failed }"
      ref="provider"
      :name="name"
      :vid="name"
      :rules="rules">
      <div class="label-wrapper">
        <label
          :for="id"
          class="control-label"
          :class="{ failed }">
          <span>{{ label }}</span>
        </label>
        <span v-if="failed">
          —{{ errors[0] }}
        </span>
      </div>

      <slot v-bind:provider="$refs.provider"></slot>

      <div class="meta" v-if="helpText || maxlength">
        <div
          v-if="helpText"
          class="help-text">
          —<span v-html="helpText" />
        </div>
        <div
          v-if="maxlength"
          class="max-length">
          {{ maxlength - value.length }}
        </div>
      </div>
    </ValidationProvider>
    <slot name="outsideValidator"></slot>
  </div>
</template>

<script>
export default {
  props: {
    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String
    },

    maxlength: {
      type: Number,
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
      type: [String, Number, File, Object, Array, Boolean],
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
  .field-wrapper {
    width: 100%;
    margin-bottom: 40px;

    .label-wrapper {
      display: flex;
      justify-content: space-between;
      margin-bottom: 4px;

      label {
        font-weight: 500;

        &:before {
          transition: opacity 0.5s ease;
          content: '';
          opacity: 0;
          position: absolute;
          width: 13px;
          height: 13px;
          margin-top: 3px;
          background-image: url("data:image/svg+xml,%3Csvg width='13' height='13' viewBox='0 0 13 13' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='6.5' cy='6.5' r='6.5' fill='%23FF0000'/%3E%3C/svg%3E%0A");
        }

        span {
          transition: padding-left 500ms ease;
          transition-delay: 0.25s;
          padding-left: 0;
        }

        &.failed {
          position: relative;
          &:before {
            transition: opacity 0.5s ease;
            transition-delay: 0.25s;
            opacity: 1;
          }

          span {
            transition: padding-left 500ms ease;
            padding-left: 30px;
          }
        }
      }
    }

    .meta {
      display: flex;
      justify-content: space-between;
      margin-top: 10px;
    }
  }
</style>
