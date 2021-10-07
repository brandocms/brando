<template>
  <div class="statuses">
    <div
      v-for="status in visibleStatuses"
      :key="status.value"
      class="status"
      :class="{ active: val === status.value }"
      @click="setStatus(status.value)">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="12"
        height="12"
        viewBox="0 0 12 12">
        <circle
          :class="status.value"
          r="6"
          cy="6"
          cx="6" />
      </svg>
      <span class="label">{{ status.label }}</span>
    </div>
  </div>
</template>

<script>
export default {
  props: {
    val: {
      type: String,
      required: true
    },
    deleted: {
      type: Boolean,
      default: false
    }
  },

  data () {
    return {
      statuses: {
        draft: {
          label: this.$t('status-draft'),
          value: 'draft'
        },

        pending: {
          label: this.$t('status-pending'),
          value: 'pending'
        },

        published: {
          label: this.$t('status-published'),
          value: 'published'
        },

        disabled: {
          label: this.$t('status-disabled'),
          value: 'disabled'
        },

        deleted: {
          label: this.$t('status-deleted'),
          value: 'deleted'
        }
      }
    }
  },

  computed: {
    visibleStatuses() {
      if (this.deleted) {
        return this.statuses
      } else {
        const { deleted, ...rest } = this.statuses
        return rest
      }
    }
  },

  methods: {
    setStatus (status) {
      if (status === this.val) {
        status = 'all'
      }
      this.$emit('statusUpdate', status)
    }
  }
}
</script>

<style lang="postcss" scoped>
  .statuses {
    display: flex;
    height: 100%;
    margin-right: 5px;
    min-height: 52px;
  }

  .status {
    @font mono;
    background-color: theme(colors.input);
    align-items: center;
    display: flex;
    cursor: pointer;
    user-select: none;
    font-size: 14px;
    text-transform: uppercase;
    padding-left: 15px;
    padding-right: 15px;
    height: 100%;

    &.active {
      background-color: theme(colors.peachDarker);
    }
  }

  .label {
    line-height: 1;
    padding-top: 1px;
  }

  svg {
    margin-right: 9px;

    circle {
      fill: theme(colors.status.published);

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

      &.deleted {
        fill: #111;
      }
    }
  }
</style>

<i18n>
{
  "en": {
    "status-draft": "Draft",
    "status-pending": "Pending",
    "status-published": "Published",
    "status-disabled": "Disabled",
    "status-deleted": "Deleted"
  },

  "no": {
    "status-draft": "Utkast",
    "status-pending": "Venter",
    "status-published": "Publisert",
    "status-disabled": "Deaktivert",
    "status-deleted": "Slettet"
  }
}
</i18n>
