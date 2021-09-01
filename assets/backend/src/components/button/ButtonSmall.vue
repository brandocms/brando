<template>
  <router-link
    v-if="to"
    class="small"
    :class="{static: position === 'static'}"
    :to="to">
    <slot></slot>
  </router-link>
  <button
    v-else
    type="button"
    :class="{static: position === 'static'}"
    class="small"
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
    }
  }
}
</script>

<style lang="postcss" scoped>
  button.small, a.small {
    margin-left: auto;
    border: 1px solid theme(colors.dark);
    color: theme(colors.dark);
    font-size: 14px;
    float: right;
    display: inline-block;
    text-transform: uppercase;
    padding: 4px 7px 4px;
    margin-top: -2px;
    transition: background-color 0.35s ease, color 0.35s ease;

    &.static {
      position: static;
    }

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.peach);
    }
  }
</style>
