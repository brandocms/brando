<template>
  <div class="svg-icon">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 100 100">
      <path d="M66.3 45.9l-2.9-2.8-13.3 13.6-13.5-13.3-2.8 2.9 16.4 16z" />
      <path d="M50 90c22.1 0 40-17.9 40-40S72.1 10 50 10 10 27.9 10 50s17.9 40 40 40zm0-76c19.9 0 36 16.1 36 36S69.9 86 50 86 14 69.9 14 50s16.1-36 36-36z" />
    </svg>
  </div>
</template>

<script>
import { TweenMax } from 'gsap'
export default {
  props: {
    open: {
      type: Boolean,
      default: false
    }
  },

  watch: {
    open (val) {
      this.toggle(val)
    }
  },

  mounted () {
    this.toggle(this.open)
  },

  methods: {
    toggle (val) {
      if (val) {
        TweenMax.to(this.$el, 0.5, { rotation: '0' })
      } else {
        TweenMax.to(this.$el, 0.5, { rotation: '-=90' })
      }
    }
  }
}
</script>
