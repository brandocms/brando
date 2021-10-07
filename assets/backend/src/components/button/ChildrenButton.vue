<template>
  <div>
    <button
      type="button"
      data-testid="children-button"
      :class="{ active }"
      @click.stop.prevent="clickHandler">
      <template v-if="active">
        {{ $t('close') }}
      </template>
      <template v-else>
        + {{ length }} <slot></slot>
      </template>
    </button>
  </div>
</template>

<script>
export default {
  props: {
    length: {
      type: [Number],
      default: 0
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
        const idx = this.visibleChildren.indexOf(this.id)
        this.visibleChildren.splice(idx, 1)
      }
    }
  }
}
</script>

<i18n>
{
  "en": {
    "close": "Close"
  },
  "no": {
    "close": "Lukk"
  }
}
</i18n>

<style lang="postcss" scoped>
  a {
    padding-top: 16px;
    display: inline-block;
  }

  button {
    padding-top: 10px;
  }

  button, a {
    @fontsize sm/1;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 48px;
    border-radius: 30px;
    padding-bottom: 9px;
    padding-left: 25px;
    padding-right: 25px;
    user-select: none;
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

  div {
    justify-content: center;
    display: flex;
  }
</style>
