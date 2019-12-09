<template>
  <button
    type="button"
    :class="{ active }"
    @click.prevent="clickHandler">
    <template v-if="active">
      Lukk
    </template>
    <template v-else>
      +{{ length }} <slot></slot>
    </template>
  </button>
</template>

<script>
export default {
  props: {
    length: {
      type: [Number]
    },

    id: {
      type: [Number, String],
      required: true
    },

    visibleChildren: {
      type: [Array],
      required: true
    }
  },

  data () {
    return {
      active: false
    }
  },

  methods: {
    clickHandler () {
      this.active = !this.active
      if (this.active) {
        this.visibleChildren.push(this.id)
      } else {
        let idx = this.visibleChildren.indexOf(this.id)
        this.visibleChildren.splice(idx, 1)
      }
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
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 60px;
    border-radius: 30px;
    padding-bottom: 0px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &.active {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
      color: theme(colors.peach);
    }

    &:hover {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
      color: theme(colors.peach);
    }
  }
</style>
