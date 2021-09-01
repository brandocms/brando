<template>
  <router-link
    v-if="to"
    :class="{ loading }"
    :to="to">
    <template v-if="loading">
      <svg
        id="L9"
        version="1.1"
        xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink"
        x="0px"
        y="0px"
        viewBox="0 0 100 100"
        enable-background="new 0 0 0 0"
        xml:space="preserve">
        <path
          fill="#fff"
          d="M73,50c0-12.7-10.3-23-23-23S27,37.3,27,50 M30.9,50c0-10.5,8.5-19.1,19.1-19.1S69.1,39.5,69.1,50">
          <animateTransform
            attributeName="transform"
            attributeType="XML"
            type="rotate"
            dur="1s"
            from="0 50 50"
            to="360 50 50"
            repeatCount="indefinite" />
        </path>
      </svg>
    </template>
    <template v-else>
      <slot></slot>
    </template>
  </router-link>
  <button
    v-else
    type="button"
    :class="{ dark, loading }"
    @click.prevent="handleClick">
    <template v-if="loading">
      <svg
        id="L9"
        version="1.1"
        xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink"
        x="0px"
        y="0px"
        viewBox="0 0 100 100"
        enable-background="new 0 0 0 0"
        xml:space="preserve">
        <path
          fill="#fff"
          d="M73,50c0-12.7-10.3-23-23-23S27,37.3,27,50 M30.9,50c0-10.5,8.5-19.1,19.1-19.1S69.1,39.5,69.1,50">
          <animateTransform
            attributeName="transform"
            attributeType="XML"
            type="rotate"
            dur="1s"
            from="0 50 50"
            to="360 50 50"
            repeatCount="indefinite" />
        </path>
      </svg>
    </template>
    <template v-else>
      <slot></slot>
    </template>
  </button>
</template>

<script>
export default {
  props: {
    loading: {
      type: Boolean,
      default: false
    },

    to: {
      type: [Object, Boolean],
      default: null
    },

    dark: {
      type: Boolean,
      default: false
    }
  },

  methods: {
    handleClick (e) {
      e.preventDefault()
      if (!this.loading) {
        this.$emit('click')
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  a {
    padding-top: 17px;
    display: inline-block;
    font-weight: 300;
  }

  button {
    padding-top: 6px;
  }

  button, a {
    font-size: 20px;
    color: theme(colors.peach);
    border: 1px solid theme(colors.blue);
    background-color: theme(colors.blue);
    border-radius: 30px;
    height: 60px;
    padding-bottom: 6px;
    padding-left: 25px;
    padding-right: 25px;
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

    &.loading {
      background-color: theme(colors.gray);
      border: 1px solid theme(colors.gray);

      svg {
        margin: 0 auto;
        margin-top: -4px;
        height: 49px;
      }
    }

    &:hover {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
    }
  }
</style>
