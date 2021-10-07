<template>
  <transition
    appear
    @beforeEnter="beforeEnter"
    @enter="enter">
    <section
      id="navigation"
      ref="nav">
      <div
        id="navigation-content"
        ref="navContent">
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
      if (process.env.NODE_ENV !== 'development') {
        const els = [this.$refs.header.$el, this.$refs.menu.$el]
        gsap.set(els, { autoAlpha: 0, x: -15 })
      }
    },

    enter (el, done) {
      const els = [this.$refs.header.$el, this.$refs.menu.$el]
      const tl = gsap.timeline({
        onComplete: done, paused: true
      })
      if (process.env.NODE_ENV !== 'development') {
        gsap.set(this.$refs.nav, { yPercent: -100, opacity: 1 })
        tl.to(this.$refs.nav, { yPercent: 0, duration: 0.7, ease: 'expo.in', delay: 0.6 })
        tl.to(els, { duration: 0.75, autoAlpha: 1, x: 0, stagger: 0.1 })

        tl.play()
      } else {
        gsap.set([this.$refs.nav, els], { opacity: 1 })
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  #navigation {
    @responsive desktop_xl { width: 370px }
    @responsive desktop_lg { width: 370px }
    @responsive desktop_md { width: 330px }
    @responsive ipad_landscape { width: 330px }
    @responsive mobile { width: 330px }
    @responsive iphone { width: 330px }
    @space padding-x sm;

    background-color: #ffffff;
    border-right: 1px solid theme(colors.dark);

    flex-shrink: 0;
    flex-grow: 0;

    height: 0;
    overflow-y: auto;
    opacity: 0;

    #navigation-content {
      @space padding-bottom md;
      @space padding-top sm;
    }
  }

</style>
