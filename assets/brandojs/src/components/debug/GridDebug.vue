<template>
  <div
    :class="{ visible }"
    class="dbg-grid"
    v-shortkey.push="['ctrl', 'g']" @shortkey="toggle">
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

  created () {
    console.log('GridDebug')
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
