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
                @click="cancel">
                {{ cancelText }}
              </button>
              <button
                type="button"
                class="btn btn-primary"
                data-dismiss="modal"
                @click="ok">
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
    // 为true时无法通过点击遮罩层关闭modal
    force: {
      type: Boolean,
      default: false
    },
    // 自定义组件transition
    transition: {
      type: String,
      default: 'modal'
    },
    // 确认按钮text
    okText: {
      type: String,
      default: 'OK'
    },
    // 取消按钮text
    cancelText: {
      type: String,
      default: 'Tilbake'
    },
    // 确认按钮className
    okClass: {
      type: String,
      default: 'btn blue'
    },
    // 取消按钮className
    cancelClass: {
      type: String,
      default: 'btn red btn-outline'
    },
    // 点击确定时关闭Modal
    // 默认为false，由父组件控制prop.show来关闭
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
