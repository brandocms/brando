<template><span /></template>
<script>
import nprogress from 'nprogress'

export default {
  props: {
    parent: {
      type: String,
      default: null
    }
  },
  created () {
    if (this.parent) {
      nprogress.configure({ parent: this.parent })
    }
    this.$router.beforeEach((to, from, next) => {
      nprogress.start()
      next()
    })
    this.$router.afterEach(() => {
      nprogress.done()
    })
  }
}
</script>
