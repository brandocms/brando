<template>
  <router-link
    v-if="to"
    :to="to">
    <slot></slot>
  </router-link>
  <button
    v-else
    type="button"
    @click.prevent="$emit('click')">
    <slot></slot>
  </button>
</template>

<script>
export default {
  props: {
    to: {
      type: [Object, Boolean]
    }
  }
}
</script>

<style lang="postcss" scoped>
  a {
    padding-top: 15.5px; /* was 18px */
    display: inline-block;
  }

  button {
    padding-top: 5px;
  }

  button, a {
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 60px;
    padding-bottom: 0px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &:hover {
      background-color: theme(colors.peach);
    }

    + button, + a {
      margin-left: -1px;
    }
  }
</style>
