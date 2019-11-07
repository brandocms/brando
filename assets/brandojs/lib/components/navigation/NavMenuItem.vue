<template>
  <div
    ref="wrapper"
    class="menu-line-wrapper">
    <div class="menu-line">
      <div
        class="caption"
        @click.stop.prevent="toggle">
        <span class="nav-icon">
          <i :class="icon ? icon : ''" />
        </span>
        {{ text }}
      </div>
    </div>
    <div class="menu-line-sub">
      <slot />
    </div>
  </div>
</template>
<script>

// import { mapGetters } from 'vuex'

export default {
  props: {
    text: {
      type: String,
      default: ''
    },
    icon: {
      type: String,
      default: ''
    }
  },

  created () {
    console.debug('created <NavMenuItem />')
  },

  methods: {
    toggle () {
      let open = this.$refs.wrapper.classList.contains('open')
      if (!open) {
        this.$emit('expanding')
        this.$refs.wrapper.classList.add('open')
      } else {
        this.$emit('contracting')
        this.$refs.wrapper.classList.remove('open')
      }
    }
  }
}
</script>
