<template>
  <transition
    @beforeEnter="beforeEnter"
    @enter="enter" appear>
    <form>
      <ValidationObserver
        ref="observer">
        <template v-slot>
          <slot>
          </slot>
          <div class="row">
            <div class="half buttons">
              <ButtonPrimary
                v-shortkey="['meta', 's']"
                @shortkey.native="validate"
                @click="validate">
                Lagre (⌘S)
              </ButtonPrimary>
              <ButtonSecondary
                :to="back">
                &larr; {{ backText }}
              </ButtonSecondary>
            </div>
          </div>
        </template>
      </ValidationObserver>
    </form>
  </transition>
</template>

<script>

import { gsap } from 'gsap'

export default {
  props: {
    back: {
      type: [Object, Boolean]
    },

    backText: {
      type: String,
      default: 'Tilbake til oversikten'
    }
  },

  mounted () {
    const fields = this.$el.querySelectorAll('.field-wrapper')
    gsap.set(fields, { autoAlpha: 0, x: -15 })
  },

  methods: {
    async validate () {
      const isValid = await this.$refs.observer.validate()
      if (!isValid) {
        this.$alerts.alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
        this.loading = false
        return
      }
      this.$emit('save')
    },

    beforeEnter (el) {

    },

    enter (el, done) {
      const fields = el.querySelectorAll('.field-wrapper')

      gsap.to(fields, { duration: 0.5, autoAlpha: 1, x: 0, stagger: '0.05' })
    }
  }
}
</script>

<style lang="postcss" scoped>
  .buttons {
    @space margin-top sm;
    display: flex;
    justify-content: space-between;

    > * {
      width: 50%;

      &:nth-child(2) {
        margin-left: 15px;
      }
    }
  }
</style>
