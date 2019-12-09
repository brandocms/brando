<template>
  <nav ref="nav">
    <div class="nav-circle" ref="circle"></div>
    <div
      class="nav-sections"
      ref="sections">
      <NavigationMenuSection
        v-for="section in $menu.sections"
        :key="section.name"
        :section="section" />
    </div>
  </nav>
</template>

<script>
import { gsap } from 'gsap'

import NavigationMenuSection from './NavigationMenuSection'

export default {
  components: {
    NavigationMenuSection
  },

  data () {
    return {

    }
  },

  mounted () {
    const dls = this.$refs.nav.querySelectorAll('dl')
    this.$refs.sections.addEventListener('mouseover', () => { this.showCircle() })
    this.$refs.sections.addEventListener('mouseleave', () => { this.hideCircle() })
    Array.from(dls).forEach(dl => {
      dl.addEventListener('mouseover', () => this.moveCircle(dl))
    })
  },

  methods: {
    showCircle () {
      gsap.to(this.$refs.circle, { duration: 0.35, opacity: 0.5 })
    },

    hideCircle () {
      gsap.to(this.$refs.circle, { duration: 0.35, opacity: 0 })
    },

    moveCircle (el) {
      const top = el.offsetTop
      gsap.to(this.$refs.circle, { ease: 'expo.ease', duration: 0.35, top: top })
    }
  }
}
</script>

<style lang="postcss" scoped>
  nav {
    .nav-circle {
      position: absolute;
      background-image: url("data:image/svg+xml,%3Csvg width='24' height='24' viewBox='0 0 24 24' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='12' cy='12' r='11.5' stroke='%230047FF'/%3E%3C/svg%3E%0A");
      width: 24px;
      height: 24px;
      opacity: 0;
      margin-top: 3px;
      margin-left: -37px;
    }
  }
</style>
