<template>
  <portal to="modals">
    <div
      ref="modalWrapper"
      class="kmodal">
      <div
        ref="modalBg"
        class="kmodal__bg"></div>
      <div
        ref="modalModal"
        :class="{ wide, kmodal__modal: true }">
        <div class="kmodal__modal__header">
          <slot name="header"></slot>
        </div>

        <div class="kmodal__modal__content">
          <slot></slot>
        </div>

        <div class="kmodal__modal__footer">
          <slot name="footer">
            <ButtonPrimary
              v-if="hasOKListener"
              @click="$emit('ok')">
              {{ okText }}
            </ButtonPrimary>

            <ButtonSecondary
              v-if="hasCancelListener"
              @click="$emit('cancel')">
              {{ cancelText }}
            </ButtonSecondary>
          </slot>
        </div>
      </div>
    </div>
  </portal>
</template>

<script>
import { gsap } from 'gsap'
export default {
  name: 'KModal',

  props: {
    okText: {
      type: String,
      required: false,
      default: function () {
        return this.$t('ok')
      }
    },

    cancelText: {
      type: String,
      required: false,
      default: function () {
        return this.$t('close')
      }
    },

    wide: {
      type: Boolean,
      default: false
    }
  },

  computed: {
    hasOKListener () {
      return this.$listeners && this.$listeners.ok
    },
    hasCancelListener () {
      return this.$listeners && this.$listeners.cancel
    }
  },

  mounted () {
    this.$nextTick().then(
      this.$nextTick(() => {
        const timeline = gsap.timeline()
        gsap.set(this.$refs.modalModal, { y: 40 })

        timeline
          .to(this.$refs.modalBg, { opacity: 0.8, duration: 0.25, ease: 'sine.in' })
          .to(this.$refs.modalModal, { opacity: 1, duration: 0.25, ease: 'none' }, '-=0.1')
          .to(this.$refs.modalModal, { y: 0, duration: 0.25, ease: 'circ.out' }, '<')
      })
    )
  },

  methods: {
    close () {
      return new Promise((resolve, reject) => {
        const timeline = gsap.timeline()
        timeline
          .to(this.$refs.modalModal, { opacity: 0, duration: 0.25, ease: 'none' })
          .to(this.$refs.modalModal, { y: 40, duration: 0.25, ease: 'circ.in' }, '<')
          .to(this.$refs.modalBg, { opacity: 0, duration: 0.4, ease: 'sine.in' }, '<')
          .call(() => {
            return resolve()
          })
      })
    }
  }
}
</script>

<style lang="postcss" scoped>
  .kmodal {
    display: flex;
    position: fixed;
    top: 0;
    left: 0;
    z-index: 99997;
    width: 100%;
    height: 100%;
    align-items: center;
    justify-content: center;
    opacity: 1;

    & >>> input[type="checkbox"] {
      width: auto !important;
    }

    & >>> input[type="radio"] {
      width: auto !important;
    }

    & >>> input[type="text"] {
      font-size: 18px;
    }

    & >>> label {
      font-size: 17px;
    }

    & >>> .label-wrapper span {
      font-size: 17px;
    }

    & >>> .help-text {
      font-size: 16px;
    }

    & >>> .multiselect > div > span {
      font-size: 17px;
    }

    & >>> input::-webkit-input-placeholder {
      font-size: 18px;
    }
    & >>> input:-ms-input-placeholder {
      font-size: 18px;
    }
    & >>> input:-moz-placeholder {
      font-size: 18px;
    }
    & >>> input::-moz-placeholder {
      font-size: 18px;
    }

    & >>> .btn-secondary {
      font-size: 18px;
    }

    &__bg {
      opacity: 0;
      background-color: theme(colors.blue);
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      z-index: 99998;
    }

    &__modal {
      display: flex;
      flex-direction: column;
      z-index: 99999;
      opacity: 0;
      max-height: 90vh;
      max-width: 80vw;
      min-width: 450px;
      border-radius: 15px;

      box-shadow:
        0 2.8px 2.2px rgba(0, 0, 0, 0.045),
        0 6.7px 5.3px rgba(0, 0, 0, 0.065),
        0 12.5px 10px rgba(0, 0, 0, 0.08),
        0 22.3px 17.9px rgba(0, 0, 0, 0.095),
        0 41.8px 33.4px rgba(0, 0, 0, 0.115),
        0 100px 80px rgba(0, 0, 0, 0.16)
      ;

      &.wide {
        min-width: 900px;
      }

      &__header {
        @fontsize lg;
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 1rem 1.75rem;
        background-color: #ffffff;
        border-bottom: 1px solid #efefef;
        border-radius: 15px 15px 0 0;

        button {
          font-size: 17px;
          padding: 10px 17px;
          min-width: auto;
        }
      }

      &__content {
        overflow-y: auto;
        background-color: white;
        padding: 1rem 1.75rem;
        position: relative;

        button + button {
          margin-top: -1px;
        }

        & >>> .panes {
          /* display: grid;
          grid-template-columns: repeat(auto-fit, minmax(250px, 450px)); */
          display: flex;
          flex-wrap: nowrap;

          > * {
            min-width: 450px;
            max-width: 450px;
            flex-grow: 0;

            &:nth-child(2) {
              padding-left: 1rem;
            }
          }
        }

        .field-wrapper {
          margin-bottom: 20px;
        }

        .shaded {
          background-color: #fafafa;
        }

        & >>> .display-icon {
          width: 100%;

          svg {
            width: 50%;
            margin-left: 25%;
            height: 100%;
            pointer-events: none;
          }
        }
      }

      &__footer {
        padding: 1rem 1.75rem;
        background-color: #ffffffe0;
        border-radius: 0 0 15px 15px;

        button + button {
          margin-left: 10px;
        }
      }
    }
  }
</style>
<i18n>
{
  "en": {
    "ok": "OK",
    "close": "Close"
  },
  "no": {
    "ok": "OK",
    "close": "Lukk"
  }
}
</i18n>
