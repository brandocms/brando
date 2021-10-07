<template>
  <div :class="compact ? '' : 'field-wrapper'">
    <ValidationProvider
      ref="provider"
      v-slot="{ errors, failed }"
      :name="name"
      :immediate="true"
      :vid="name"
      :rules="rules">
      <template v-if="compact">
        <div class="compact">
          <slot :provider="$refs.provider"></slot>
          <div
            v-if="label"
            class="label-wrapper">
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
        </div>
      </template>
      <template v-else>
        <div
          v-if="label"
          class="label-wrapper">
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
        <slot :provider="$refs.provider"></slot>
      </template>
    </ValidationProvider>
    <slot name="outsideValidator"></slot>
    <div
      v-if="helpText || maxlength"
      class="meta">
      <div
        v-if="helpText"
        class="help-text">
        —<span v-html="helpText" />
      </div>
      <div
        v-if="maxlength"
        class="max-length">
        {{ maxlength - (value ? value.length : 0) }}
      </div>
      <div
        v-if="characterCount"
        class="character-count">
        {{ value ? value.length : 0 }}
      </div>
    </div>
  </div>
</template>

<script>
export default {
  props: {
    helpText: {
      type: String,
      default: null
    },

    compact: {
      type: Boolean,
      default: false
    },

    label: {
      type: String,
      default: null
    },

    maxlength: {
      type: Number,
      default: null
    },

    characterCount: {
      type: Boolean,
      default: false
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
  .compact {
    display: flex;
    align-items: center;

    >>> .check-wrapper {
      margin-top: 0 !important;
      margin-right: 15px;

      .form-check {
        margin-bottom: 0 !important;
      }
    }

    >>> .label-wrapper {
      margin-bottom: 0 !important;
    }
  }

  .field-wrapper {
    width: 100%;
    margin-bottom: 40px;

    .label-wrapper {
      display: flex;
      justify-content: space-between;
      margin-bottom: 4px;

      > span {
        font-size: 16px;
      }

      label {
        @fontsize form.label;
        font-weight: 500;

        &:before {
          transition: opacity 0.5s ease;
          content: '';
          opacity: 0;
          position: absolute;
          top: 1px;
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

      .help-text {
        @fontsize form.help;
      }

      .character-count {
        font-size: 12px;
        border: 1px solid theme(colors.dark);
        border-radius: 16px;
        padding: 3px 5px 2px;
      }
    }
  }
</style>
