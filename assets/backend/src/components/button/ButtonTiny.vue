<template>
  <router-link
    v-if="to"
    class="tiny"
    :class="{static: position === 'static', right}"
    :to="to">
    <slot></slot>
  </router-link>
  <button
    v-else
    type="button"
    :class="{static: position === 'static', right}"
    class="tiny"
    @click.prevent="$emit('click')">
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
    position: {
      type: String,
      default: 'absolute'
    },

    right: {
      type: Boolean,
      default: false
    }
  }
}
</script>

<style lang="postcss" scoped>
  button.tiny, a.tiny {
    @font mono;
    border-radius: 5px;
    border: 1px solid theme(colors.dark);
    color: theme(colors.dark);
    font-size: 11px;
    display: inline-block;
    text-transform: uppercase;
    padding: 4px 7px 4px;
    margin-top: -2px;
    transition: background-color 0.35s ease, color 0.35s ease;

    &.right {
      margin-left: auto;
    }

    &.static {
      position: static;
    }

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.peach);
    }
  }
</style>
