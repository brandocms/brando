<template>
  <router-link
    v-if="to"
    :to="to">
    <slot></slot>
  </router-link>
  <button
    v-else
    type="button"
    :class="{ dark }"
    @click.prevent="$emit('click')">
    <slot></slot>
  </button>
</template>

<script>
export default {
  props: {
    to: {
      type: [Object, Boolean]
    },

    dark: {
      type: Boolean,
      default: false
    }
  }
}
</script>

<style lang="postcss" scoped>
  a {
    padding-top: 18px;
    display: inline-block;
  }

  button {
    padding-top: 5px;
  }

  button, a {
    color: theme(colors.peach);
    border: 1px solid theme(colors.blue);
    background-color: theme(colors.blue);
    height: 60px;
    border-radius: 30px;
    padding-bottom: 0px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &.dark {
      background-color: theme(colors.dark);
      border: 1px solid theme(colors.dark);
      color: theme(colors.peach);

      &:hover {
        background-color: black;
        color: theme(colors.peach);
      }
    }

    &:hover {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
    }
  }
</style>
