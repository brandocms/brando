<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :help-text="helpText"
    :value="value">
    <template #default>
      <div
        v-if="options.length"
        class="radios-wrapper">
        <div
          v-for="o in options"
          :key="o.value"
          class="form-check">
          <label class="form-check-label">
            <input
              v-model="innerValue"
              :data-testid="`status-${o.value}`"
              :name="name"
              :value="o.value"
              class="form-check-input"
              type="radio">
            <span
              class="label-text"
              :class="o.value">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="12"
                height="12"
                viewBox="0 0 12 12">
                <circle
                  :class="o.value"
                  r="6"
                  cy="6"
                  cx="6" />
              </svg>{{ o.label }}</span>
          </label>
        </div>
      </div>
    </template>
  </KFieldBase>
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
      options: [
        { value: 'draft', label: this.$t('draft') },
        { value: 'pending', label: this.$t('pending') },
        { value: 'published', label: this.$t('published') },
        { value: 'disabled', label: this.$t('deactivated') }
      ]
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
  .radios-wrapper {
    margin-top: 8px;

    .form-check {
      margin-bottom: 5px;
    }

    input {
      margin-right: 17px;
      margin-top: 8px;
    }

    label {
      display: inline-block;

      span {
        display: inline-flex;
        align-items: center;
      }
    }
  }

  svg {
    margin-right: 12px;
    margin-top: -4px;
    circle {
      fill: theme(colors.blue);

      &.draft {
        fill: theme(colors.status.draft);
      }

      &.pending {
        fill: theme(colors.status.pending);
      }

      &.published {
        fill: theme(colors.status.published);
      }

      &.disabled {
        fill: theme(colors.status.disabled);
      }
    }
  }

  .label-text {
    font-size: 17px;
    border: 1px solid;
    padding: 2px 14px;
    padding-top: 5px;
    border-radius: 30px;

    &.draft {
      border-color: theme(colors.status.draft);
    }

    &.pending {
      border-color: theme(colors.status.pending);
    }

    &.published {
      border-color: theme(colors.status.published);
    }

    &.disabled {
      border-color: theme(colors.status.disabled);
    }
  }
</style>

<i18n>
  {
    "en": {
      "draft": "Draft",
      "pending": "Pending",
      "published": "Published",
      "deactivated": "Deactivated"
    },

    "no": {
      "draft": "Utkast",
      "pending": "Venter",
      "published": "Publisert",
      "deactivated": "Deaktivert"
    }
  }
</i18n>
