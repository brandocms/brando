<template>
  <article
    v-if="show"
    class="checkorx">
    <FontAwesomeIcon
      class="icon"
      :icon="val ? 'check' : 'times'"
      size="xs"
      fixed-width />
    <div
      v-if="label"
      class="label">
      {{ label }}
    </div>
  </article>
</template>

<script>

export default {
  props: {
    label: {
      type: String,
      default: null
    },

    val: {
      type: [Number, String, Object, Array, Boolean],
      required: true
    },

    hideFalse: {
      type: Boolean,
      default: false
    }
  },

  computed: {
    show () {
      if (this.hideFalse && this.val === false) {
        return false
      }
      return true
    }
  },

  methods: {
  }
}
</script>

<style lang="postcss" scoped>
  .checkorx {
    display: inline-flex;
    align-items: center;
    justify-content: space-between;
    border-radius: 25px;
    border: 1px solid theme(colors.dark);
    padding: 7px 10px;

    .icon + .label {
      margin-left: 7px;
      padding-right: 5px;
      padding-top: 1px;
    }

    .label {
      @font mono xs(0.85)/1;
      text-transform: uppercase;
    }

    & + .checkorx {
      margin-top: 5px;
    }
  }
</style>
