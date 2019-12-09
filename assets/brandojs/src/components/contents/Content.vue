<template>
  <transition
    @beforeAppear="beforeAppear"
    @appear="appear">

    <main>
      <GridDebug />
      <transition
        mode="out-in"
        @beforeAppear="beforeAppearContent"
        @appear="appearContent"
        @afterLeave="afterLeave"
        @leave="leave"
        v-bind:css="false"
        appear>
        <router-view class="content" />
      </transition>
    </main>
  </transition>
</template>

<script>

import { gsap } from 'gsap'
import GridDebug from '../debug/GridDebug'

export default {
  name: 'Content',
  components: {
    GridDebug
  },

  methods: {
    afterLeave () {
      window.scrollTo(0, 0)
    },

    beforeAppear (el) {
      gsap.set(el, { yPercent: -100 })
    },

    appear (el, done) {
      const tl = gsap.timeline({
        onComplete: done
      })

      tl
        .to(el, {
          duration: 0.7,
          yPercent: 0,
          delay: 1.4,
          ease: 'power3.out'
        })
    },

    beforeAppearContent (el) {
      gsap.set(el, { x: -25, autoAlpha: 0 })
    },

    appearContent (el, done) {
      const tl = gsap.timeline({
        onComplete: done
      })

      tl.to(el, {
        duration: 0.7,
        x: 0,
        delay: 2,
        autoAlpha: 1,
        ease: 'power3.out'
      })
    },

    leave (el, done) {
      console.log('leave')
      const tl = gsap.timeline({
        onComplete: done
      })

      tl.to(el, {
        duration: 0.2,
        autoAlpha: 0
      })
    }
  }
}
</script>

<style lang="postcss">
  main {
    position: relative;
    width: 100%;
    min-height: 100vh;
    background-color: #ffffff;

    > .content {
      @space padding-left md;
      @space padding-right md;
      @space padding-bottom md;
    }
  }

  .fader-1, .fader-2 {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    z-index: 100;
  }

  .fader-1 {
    /* background-color: theme(colors.peachDarker); */
    background-color: blue;
    z-index: 101;
  }

  .fader-2 {
    /* background-color: theme(colors.peachDarkest); */
    z-index: 102;
    background-color: red;
  }
</style>
