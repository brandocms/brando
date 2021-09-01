<template>
  <div>
    <div
      v-if="loggedWarnings"
      class="logged-warnings-count"
      @click="toggle">
      <FontAwesomeIcon
        v-if="loggedWarnings.length"
        color="#f00"
        icon="exclamation-circle"
        size="xs" />
      <FontAwesomeIcon
        v-else
        color="#75ce75d6"
        icon="check-circle"
        size="xs" />
      {{ loggedWarnings.length ? loggedWarnings.length : '' }}
    </div>
    <div
      class="logged-warnings-drawer"
      :class="{open: show}">
      <div class="inner">
        <div
          v-for="(w, idx) in loggedWarnings"
          :key="idx"
          class="logged-warnings-line">
          {{ w.msg }}
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  props: {
    loggedWarnings: {
      type: Array,
      required: true
    }
  },

  data () {
    return {
      show: false
    }
  },

  methods: {
    toggle () {
      if (!this.loggedWarnings.length && !this.show) {
        return
      }
      this.show = !this.show
    }
  }
}
</script>

<style lang="postcss" scoped>
  .logged-warnings-count {
    @color fg dark;
    @color bg peachLighter;
    @font mono;
    position: fixed;
    bottom: 10px;
    right: 10px;
    font-size: 14px;
    padding: 4px 8px;
    border-radius: 15px;
    z-index: 99;
    cursor: pointer;
  }

  .logged-warnings-drawer {
    height: 100vh;
    width: 650px;
    position: fixed;
    right: 0;
    transform: translateX(100%);
    top: 0;
    background-color: #052753;
    color: azure;
    overflow-x: hidden;
    overflow-y: scroll;
    transition: transform 0.6s cubic-bezier(0.5, 0, 0.75, 0);

    &.open {
      transform: translateX(0%);
      transition: transform 0.6s cubic-bezier(0.25, 1, 0.5, 1);
    }

    .inner {
      @space padding 15px;
    }

    .logged-warnings-line {
      @font mono;
      font-size: 11px;
      margin-bottom: 30px;
      white-space: pre-line;
    }
  }
</style>
