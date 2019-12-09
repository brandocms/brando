<template>
  <transition
    @beforeEnter="beforeEnter"
    @enter="enter"
    appear>
    <section ref="nav" id="navigation">
      <div id="navigation-content" ref="navContent">
        <NavigationHeader ref="header" />
        <CurrentUser />
        <NavigationMenu ref="menu" />
      </div>
    </section>
  </transition>
</template>

<script>
import { gsap } from 'gsap'

import CurrentUser from '../user/CurrentUser'
import NavigationHeader from '../navigation/NavigationHeader'
import NavigationMenu from '../navigation/NavigationMenu'

export default {
  name: 'Navigation',
  components: {
    CurrentUser,
    NavigationHeader,
    NavigationMenu
  },

  methods: {
    beforeEnter (el) {
      const els = [this.$refs.header.$el, this.$refs.menu.$el]
      gsap.set(els, { autoAlpha: 0, x: -15 })
      console.log(this.$refs.nav)
    },

    enter (el, done) {
      console.log(this.$refs.nav)
      const els = [this.$refs.header.$el, this.$refs.menu.$el]
      const tl = gsap.timeline({
        onComplete: done
      })

      gsap.set(this.$refs.nav, { yPercent: -100, opacity: 1 })
      tl.to(this.$refs.nav, { yPercent: 0, duration: 0.7, ease: 'expo.in', delay: 0.6 })
      tl.to(els, { duration: 0.75, autoAlpha: 1, x: 0, stagger: 0.1 })
    }
  }
}
</script>

<style lang="postcss" scoped>
  #navigation {
    @space padding-x md;
    background-color: theme(colors.peach);
    flex-shrink: 0;
    flex-grow: 0;
    width: 370px;
    height: 0;
    overflow-y: auto;
    opacity: 0;

    #navigation-content {
      @space padding-bottom md;
      @space padding-top sm;
    }
  }
</style>
