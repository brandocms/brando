<template>
  <div
    v-shortkey.push="['ctrl', 'g']"
    :class="{ visible }"
    class="dbg-grid"
    @shortkey="toggle">
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
    <b></b>
  </div>
</template>

<script>
export default {
  data () {
    return {
      visible: false
    }
  },

  methods: {
    toggle () {
      this.visible = !this.visible
    }
  }
}
</script>

<style lang="postcss">
  .dbg-grid {
    position: absolute !important;
    display: none;

    &.visible {
      display: grid;
    }
  }
</style>
