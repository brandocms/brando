<template>
  <router-link
    v-if="to"
    class="button-secondary"
    :class="{ narrow, fullWidth, disabled }"
    :to="disabled ? '' : to">
    <slot></slot>
  </router-link>
  <button
    v-else
    type="button"
    class="button-secondary"
    :class="{ narrow, fullWidth, disabled }"
    @click.prevent="disabled ? null : $emit('click')">
    <slot></slot>
  </button>
</template>

<script>
export default {
  props: {
    to: {
      type: [Object, Boolean],
      default: null
    },

    narrow: {
      type: Boolean,
      default: false
    },

    disabled: {
      type: Boolean,
      default: false
    },

    fullWidth: {
      type: Boolean,
      default: false
    }
  }
}
</script>

<style lang="postcss" scoped>
  a {
    padding-top: 14px;
    display: inline-block;
  }

  button {
    padding-top: 6px;
  }

  button, a {
    font-size: 20px;
    font-weight: 400;
    white-space: nowrap;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark) !important;
    background-color: transparent;
    padding: 15px 25px 16px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &.fullWidth {
      min-width: auto;
    }

    &.narrow {
      min-width: auto;
      padding: 15px 18px 16px;
    }

    &.disabled {
      color: #aaa;
    }

    &:hover {
      background-color: theme(colors.peach);
    }
  }

  .button-secondary + .button-secondary {
    border-left: none;
  }
</style>
