<template>
  <div class="wrapper" v-click-outside="closeContent">
    <button ref="button" :class="{ open }" type="button" @click="toggle">
      <svg width="40" height="40" viewBox="0 0 40 40" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle class="main-circle" cx="20" cy="20" r="19.5" fill="#0047FF" stroke="#0047FF"/>
        <line x1="12" y1="12.5" x2="28" y2="12.5" stroke="white"/>
        <line x1="18" y1="26.5" x2="28" y2="26.5" stroke="white"/>
        <line x1="12" y1="19.5" x2="28" y2="19.5" stroke="white"/>
        <circle cx="13.5" cy="26.5" r="1.5" fill="white"/>
      </svg>
    </button>
    <ul ref="content" class="dropdown-content">
      <slot></slot>
    </ul>
  </div>
</template>

<script>
import { gsap } from 'gsap'

export default {
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
      gsap.to(this.$refs.content, { opacity: 1, x: 0 })
    },

    closeContent () {
      this.open = false
      gsap.to(this.$refs.content, { opacity: 0,
        x: -15,
        onComplete: () => {
          gsap.set(this.$refs.content, { display: 'none' })
        } })
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
        }
        line {
          transition: stroke 0.3s ease;
          stroke: theme(colors.peach);
        }
        circle {
          transition: fill 0.3s ease;
          fill: theme(colors.peach);
        }
      }
    }

    svg {
      line {
        transition: stroke 0.3s ease;
        stroke: theme(colors.dark);
      }

      circle {
        transition: fill 0.3s ease;
        fill: theme(colors.dark);
      }

      .main-circle {
        transition: fill 0.3s ease;
        stroke: theme(colors.dark);
        fill: transparent;
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
    position: absolute;
    width: 250px;
    border: 1px solid theme(colors.dark);
    z-index: 2;

    li {
      a, button {
        display: block;
        padding: 15px 15px 11px;
        text-align: right;
        line-height: 1;
        float: right;
        width: 100%;

        &:hover {
          background-color: theme(colors.dark);
          color: theme(colors.peach);
        }
      }
    }
  }

  .wrapper {
    position: relative;
  }
</style>
