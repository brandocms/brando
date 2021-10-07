<template>
  <div
    v-click-outside="closeContent"
    class="circle-dropdown wrapper">
    <button
      ref="button"
      data-testid="circle-dropdown-button"
      type="button"
      :class="{ open }"
      @click.stop="toggle">
      <svg
        width="40"
        height="40"
        viewBox="0 0 40 40"
        fill="none"
        xmlns="http://www.w3.org/2000/svg">
        <circle
          class="main-circle"
          :class="{ inverted }"
          cx="20"
          cy="20"
          r="19.5"
          fill="#0047FF" />
        <line
          x1="12"
          y1="12.5"
          x2="28"
          y2="12.5"
          :class="{ inverted }"
          stroke="white" />
        <line
          x1="18"
          y1="26.5"
          x2="28"
          y2="26.5"
          :class="{ inverted }"
          stroke="white" />
        <line
          x1="12"
          y1="19.5"
          x2="28"
          y2="19.5"
          :class="{ inverted }"
          stroke="white" />
        <circle
          cx="13.5"
          cy="26.5"
          r="1.5"
          :class="{ inverted }"
          fill="white" />
      </svg>
    </button>
    <ul
      ref="content"
      data-testid="circle-dropdown-content"
      class="dropdown-content"
      @click.stop="closeContent">
      <slot></slot>
    </ul>
  </div>
</template>

<script>
import { gsap } from 'gsap'

export default {
  props: {
    inverted: {
      type: Boolean,
      default: false
    }
  },

  data () {
    return {
      open: false
    }
  },

  methods: {
    toggle () {
      if (this.open) {
        this.closeContent()
      } else {
        this.openContent()
      }
    },

    openContent () {
      this.open = true
      const buttonHeight = this.$refs.button.clientHeight
      gsap.set(this.$refs.content, { top: buttonHeight + 10, right: 0, opacity: 0, x: -15, display: 'block' })
      // find out where we are
      const buttonBottom = this.$refs.button.getBoundingClientRect().y + buttonHeight
      const contentRect = this.$refs.content.getBoundingClientRect()
      if (contentRect.height + buttonBottom > window.innerHeight) {
        gsap.set(this.$refs.content, { top: (contentRect.height + 10) * -1 })
      }
      gsap.to(this.$refs.content, { opacity: 1, x: 0 })
    },

    closeContent () {
      if (this.open) {
        this.open = false
        if (this.$refs.content) {
          gsap.to(this.$refs.content, {
            opacity: 0,
            x: -15,
            onComplete: () => {
              if (this.$refs.content) {
                gsap.set(this.$refs.content, { display: 'none' })
              }
            }
          })
        }
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  button {
    border: none;

    &.open {
      svg {
        .main-circle {
          fill: theme(colors.dark);

          &.inverted {
            fill: theme(colors.peach);
          }
        }
        line {
          transition: stroke 0.3s ease;
          stroke: theme(colors.peach);

          &.inverted {
            fill: theme(colors.dark);
          }
        }
        circle {
          transition: fill 0.3s ease;
          fill: theme(colors.peach);

          &.inverted {
            fill: theme(colors.dark);
          }
        }
      }
    }

    svg {
      line {
        transition: stroke 0.3s ease;
        stroke: theme(colors.dark);

        &.inverted {
          stroke: theme(colors.peach);
        }
      }

      circle {
        transition: fill 0.3s ease;
        fill: theme(colors.dark);
      }

      .main-circle {
        transition: fill 0.3s ease;
        stroke: theme(colors.dark);
        fill: transparent;

        &.inverted {
          stroke: theme(colors.peach);
        }
      }
    }

    &:hover {
      svg {
        line {
          transition: stroke 0.3s ease;
          stroke: theme(colors.peach);
        }
        circle {
          transition: fill 0.3s ease;
          fill: theme(colors.peach);
        }
        .main-circle {
          transition: fill 0.3s ease;
          fill: theme(colors.dark);
        }
      }
    }
  }

  .dropdown-content {
    display: none;
    opacity: 0;
    background-color: theme(colors.peach);
    color: theme(colors.dark);
    position: absolute;
    width: 250px;
    border: 1px solid theme(colors.dark);
    z-index: 2;

    li {
      a, button {
        @font mono;
        display: block;
        padding: 15px;
        text-align: right;
        line-height: 1;
        float: right;
        width: 100%;
        font-size: 15px;
        text-transform: uppercase;

        &:hover {
          background-color: theme(colors.dark);
          color: theme(colors.peach);
        }
      }
    }
  }

  .wrapper {
    position: relative;
    display: flex;
    justify-content: center;
  }
</style>
