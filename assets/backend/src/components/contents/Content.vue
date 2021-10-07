<template>
  <transition
    @beforeAppear="beforeAppear"
    @appear="appear">
    <main class="clearfix">
      <GridDebug />
      <div
        ref="progress"
        class="progress">
        <transition-group
          name="slide-fade"
          tag="div"
          class="progress-inner"
          appear>
          <div
            v-for="k in Object.keys(progressStatus)"
            :key="k">
            <transition
              name="fade"
              mode="out-in"
              :duration="250">
              <i
                v-if="progressStatus[k].percent !== 100"
                key="working"
                :class="'fal fa-fw mr-3 fa-cog fa-spin'" />
              <i
                v-else
                key="done"
                :class="'fal fa-fw mr-3 fa-check text-success'" />
            </transition>
            <div
              class="d-inline-block"
              v-html="progressStatus[k].content" />
            <div
              class="bar"
              :style="{ width: progressStatus[k].percent + '%' }"></div>
          </div>
        </transition-group>
      </div>
      <transition
        mode="out-in"
        :css="false"
        appear
        @beforeAppear="beforeAppearContent"
        @appear="appearContent"
        @afterLeave="afterLeave"
        @leave="leave">
        <router-view
          :key="$route.fullPath"
          class="content" />
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

  props: {
    showProgress: {
      type: Boolean,
      required: true
    },

    progressStatus: {
      type: Object,
      required: true
    }
  },

  data () {
    return {
    }
  },

  watch: {
    showProgress (val) {
      if (val) {
        this.$refs.progress.classList.add('visible')
      } else {
        this.$refs.progress.classList.remove('visible')
      }
    }
  },

  methods: {
    afterLeave () {
      window.scrollTo(0, 0)
    },

    beforeAppear (el) {
      if (process.env.NODE_ENV !== 'development') {
        gsap.set(el, { yPercent: -100 })
      }
    },

    appear (el, done) {
      const tl = gsap.timeline({
        onComplete: done,
        paused: true
      })

      tl
        .to(el, {
          duration: 0.7,
          yPercent: 0,
          delay: 1.4,
          ease: 'power3.out',
          clearProps: 'transform'
        })

      if (process.env.NODE_ENV !== 'development') {
        tl.play()
      }
    },

    beforeAppearContent (el) {
      if (process.env.NODE_ENV !== 'development') {
        gsap.set(el, { x: -25, autoAlpha: 0 })
      }
    },

    appearContent (el, done) {
      const tl = gsap.timeline({
        onComplete: done,
        paused: true
      })

      tl.to(el, {
        duration: 0.7,
        x: 0,
        delay: 2,
        autoAlpha: 1,
        ease: 'power3.out',
        clearProps: 'transform'
      })

      if (process.env.NODE_ENV !== 'development') {
        tl.play()
      }
    },

    leave (el, done) {
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
    display: flex;
    flex-direction: column;
    padding-bottom: 100px;

    > .content {
      @space padding-x sm;
      @space padding-bottom md;
      min-height: 100vh;
    }

    > .progress {
      @container;
      z-index: 999999;
      color: theme(colors.peach);
      background-color: #000080e6;
      height: auto;
      transform: translateY(-100%);
      overflow-y: scroll;
      display: flex;
      position: fixed;
      left: 0;
      padding-top: 20px;
      padding-bottom: 25px;
      transition: transform 350ms ease;

      &.visible {
        transform: translateY(0%);
      }

      .progress-inner {
        display: flex;
        flex-direction: column;
        align-items: center;
        width: 100%;

        > div {
          &:first-of-type {
            padding-top: 5px;
          }
          width: 100%;
          padding-top: 15px;
          padding-bottom: 5px;
        }
      }

      .bar {
        margin-top: 5px;
        height: 2px;
        background-color: theme(colors.peach);
        transition: width 0.75s ease;
      }
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
