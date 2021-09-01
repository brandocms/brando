<template>
  <div v-if="ready">
    <div
      class="villain-block-wrapper">
      <VillainPlus
        @add="$emit('add', $event)"
        @move="$emit('move', $event)" />
    </div>

    <transition-group
      @enter="enter"
      @leave="leave">
      <div
        v-for="(b, index) in innerValue"
        ref="containers"
        :key="`${b.uid}-container`"
        :data-uid="b.uid"
        :data-index="index"
        class="villain-block-container">
        <component
          :is="b.type + 'Block'"
          :key="b.uid"
          :block="b"
          @add="$emit('add', $event)"
          @delete="$emit('delete', $event)"
          @duplicate="$emit('duplicate', $event)"
          @hide="$emit('hide', $event)"
          @show="$emit('show', $event)"
          @move="$emit('move', $event)" />
      </div>
    </transition-group>
  </div>
</template>

<script>
import { gsap } from 'gsap'
export default {
  name: 'BlockContainer',

  props: {
    ready: {
      type: Boolean,
      default: false
    },

    value: {
      type: Array,
      default: () => []
    }
  },

  data () {
    return {
      uid: null
    }
  },

  computed: {
    innerValue: {
      get () { return this.value },
      set (innerValue) {
        this.$emit('input', innerValue)
      }
    }
  },

  created () {
    this.uid = (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
  },

  methods: {
    enter (el, done) {
      gsap.fromTo(el,
        {
          opacity: 0,
          x: -5
        },
        {
          duration: 0.25,
          opacity: 1,
          x: 0,
          onComplete: () => {
            gsap.set(el, { clearProps: 'transform' })
            done()
          }
        })
    },

    leave (el, done) {
      gsap.to(el, {

        duration: 0.45,
        opacity: 0,
        x: -5,
        onComplete: () => {
          gsap.to(el, { duration: 0.3, height: 0, onComplete: done, ease: 'power3.in' })
        }
      })
    }
  }

}
</script>
