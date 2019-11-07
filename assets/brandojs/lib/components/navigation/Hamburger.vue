<template>
  <div class="navigation-menu">
    <button
      id="hamburger"
      :class="{'is-active': status}"
      class="hamburger hamburger--spin"
      type="button"
      @click.prevent.stop="toggleMenu">
      <span class="hamburger-box">
        <span class="hamburger-inner" />
      </span>
    </button>
  </div>
</template>

<script>

import { mapGetters } from 'vuex'

export default {
  computed: {
    ...mapGetters('menu', [
      'status'
    ])
  },

  methods: {
    toggleMenu (e) {
      this.$store.commit('menu/TOGGLE_MENU')
    }
  }
}
</script>
