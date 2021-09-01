<template>
  <svg
    class="circle-filled"
    :class="{selected, 'circle-filled': true}"
    xmlns="http://www.w3.org/2000/svg"
    width="12"
    height="12"
    viewBox="0 0 12 12">
    <circle
      :class="status"
      r="6"
      cy="6"
      cx="6" />
  </svg>
</template>

<script>
export default {
  props: {
    status: {
      type: String,
      default: ''
    },

    selected: {
      type: Boolean,
      default: false
    }
  }
}
</script>

<style lang="postcss" scoped>
  svg {
    margin-right: 12px;

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
</style>
