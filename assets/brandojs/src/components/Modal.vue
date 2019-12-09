<template>
  <transition
    :duration="500"
    name="modal">
    <div
      v-show="show"
      class="modal"
      style="display: block;">
      <div
        key="backdrop"
        class="modal-backdrop"
        @click.stop="cancel" />
      <div
        v-if="chrome === true"
        ref="dialog"
        :class="modalClass"
        class="modal-dialog"
        role="document">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="section mb-0 modal-title">
              <slot name="title">
                {{ title }}
              </slot>
            </h5>
          </div>
          <div class="modal-body">
            <slot />
          </div>
          <div class="modal-footer">
            <slot name="footer">
              <button
                v-if="showCancelButton"
                type="button"
                class="btn btn-outline-primary"
                data-dismiss="modal"
                @click.stop="cancel">
                {{ cancelText }}
              </button>
              <button
                type="button"
                class="btn btn-primary"
                data-dismiss="modal"
                @click.stop="ok">
                {{ okText }}
              </button>
            </slot>
          </div>
        </div>
      </div>
      <div
        v-else
        :class="modalClass"
        class="modal-no-chrome">
        <div
          ref="dialog"
          class="modal-no-chrome-content"
          role="document">
          <slot />
        </div>
      </div>
    </div>
  </transition>
</template>

<script>
/**
 * Bootstrap Style Modal Component for Vue
 * Depend on Bootstrap.css
 */

export default {
  name: 'Modal',
  props: {
    show: {
      type: Boolean,
      twoWay: true,
      default: false
    },
    chrome: {
      type: Boolean,
      default: true
    },
    title: {
      type: String,
      default: 'Modal'
    },
    small: {
      type: Boolean,
      default: false
    },
    large: {
      type: Boolean,
      default: false
    },
    full: {
      type: Boolean,
      default: false
    },

    force: {
      type: Boolean,
      default: false
    },

    transition: {
      type: String,
      default: 'modal'
    },

    okText: {
      type: String,
      default: 'OK'
    },

    cancelText: {
      type: String,
      default: 'Tilbake'
    },

    okClass: {
      type: String,
      default: 'btn blue'
    },

    cancelClass: {
      type: String,
      default: 'btn red btn-outline'
    },

    closeWhenOK: {
      type: Boolean,
      default: true
    },

    showCancelButton: {
      type: Boolean,
      default: true
    }
  },
  data () {
    return {
      duration: null
    }
  },
  computed: {
    modalClass () {
      return {
        'modal-lg': this.large,
        'modal-sm': this.small,
        'modal-full': this.full
      }
    }
  },
  watch: {
    show (value) {
      if (value) {
        document.body.className += ' modal-open'
      } else {
        if (!this.duration) {
          this.duration = window.getComputedStyle(this.$refs.dialog)['transition-duration'].replace('s', '') * 500
        }

        window.setTimeout(() => {
          document.body.className = document.body.className.replace(/\s?modal-open/, '')
        }, this.duration || 0)
      }
    }
  },
  created () {
    if (this.show) {
      document.body.className += ' modal-open'
    }
  },
  beforeDestroy () {
    document.body.className = document.body.className.replace(/\s?modal-open/, '')
  },
  methods: {
    ok () {
      this.$emit('ok')
    },
    cancel () {
      this.$emit('cancel')
    },
    // 点击遮罩层
    clickMask () {
      if (!this.force) {
        this.cancel()
      }
    }
  }
}
</script>

<style lang="postcss">
  body.modal-open {
    overflow-y: auto;
    padding-right: 0 !important;
  }

  .modal {
    position: fixed;
    top: 0;
    left: 0;
    z-index: 1050;
    display: none;
    width: 100%;
    height: 100%;
    overflow-y: auto;
    outline: 0;
  }

  .modal {
    .card {
      position: relative;
      display: flex;
      flex-direction: column;
      min-width: 0;
      word-wrap: break-word;
      background-color: #fff;
      background-clip: border-box;
      border: 0 solid rgba(0,0,0,.125);
    }

    .text-center {
      text-align: center!important;
    }

    .card-header {
      color: #fff;
      background-color: #363e5c;
      padding: 1.5rem 1.5rem;
      margin-bottom: 0;
      border-bottom: 0 solid rgba(0,0,0,.125);
    }

    .card-block {
      background-color: #fff;
    }
    .card-body {
      flex: 1 1 auto;
      padding: 1.5rem;
    }
  }

  .modal-no-chrome {
    margin: 5% auto 0;
    position: relative;
    transition: all 0.2s ease;
    width: 400px;
    z-index: 1250;

    &.modal-lg {
      max-width: 800px;
      width: 100%;
    }
  }

  .modal-backdrop {
    background-color: rgba(98, 79, 160, 0.75);
    height: 100%;
    left: 0;
    overflow-y: scroll;
    position: fixed;
    top: 0;
    transition: all 0.5s ease;
    width: 100%;
    z-index: 1001;
  }

  .modal-dialog {
    transition: all 0.2s ease;
    z-index: 1050;
  }

  .modal-enter .modal-dialog,
  .modal-enter .modal-no-chrome,
  .modal-leave-to .modal-dialog,
  .modal-leave-to .modal-no-chrome {
    opacity: 0;
    transform: scale(1.1);
  }

  .modal-enter .modal-backdrop,
  .modal-leave-to .modal-backdrop {
    opacity: 0;
  }

  .modal-enter-to .modal-backdrop,
  .modal-leave .modal-backdrop {
    opacity: 1;
  }

  .modal-content {
    background-clip: padding-box;
    background-color: #fff;
    border: none;
    border-radius: 0;
    display: flex;
    flex-direction: column;
    outline: 0;
    padding: 0.5rem;
    position: relative;
  }

  .modal-no-chrome-content {
    display: flex;
    flex-direction: column;
    position: relative;
  }
</style>
