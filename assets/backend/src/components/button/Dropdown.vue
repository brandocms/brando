<template>
  <div
    ref="el"
    tabindex="0"
    data-testid="dropdown"
    :class="{ open: open }"
    class="dropdown"
    @click="toggle"
    @keyup.enter="toggle"
    @focus="focus">
    <section class="button">
      <section class="icon-wrapper">
        <div class="icon">
          <svg
            width="48"
            height="48"
            viewBox="0 0 48 48"
            fill="none"
            xmlns="http://www.w3.org/2000/svg">
            <circle
              cx="24"
              cy="24"
              r="23.5"
              stroke="black" />
            <line
              x1="14.4"
              y1="15.1"
              x2="33.6"
              y2="15.1"
              stroke="black" />
            <line
              x1="21.6"
              y1="31.9"
              x2="33.6"
              y2="31.9"
              stroke="black" />
            <line
              x1="14.4"
              y1="23.5"
              x2="33.6"
              y2="23.5"
              stroke="black" />
            <circle
              cx="16.2"
              cy="31.8"
              r="1.8"
              fill="black" />
          </svg>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="title">
            <slot></slot>
          </div>
        </div>
        <div class="dropdown-icon">
          <svg
            width="13"
            height="10"
            viewBox="0 0 13 10"
            fill="none"
            xmlns="http://www.w3.org/2000/svg">
            <path
              d="M6.5 10L0.00480841 0.624999L12.9952 0.624998L6.5 10Z"
              fill="black" />
          </svg>
        </div>
      </section>
    </section>
    <section
      ref="dropdownContent"
      class="dropdown-content">
      <ul>
        <slot name="content"></slot>
      </ul>
    </section>
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
      this.$nextTick(() => {
        if (this.$refs.dropdownContent) {
          const lis = this.$refs.dropdownContent.querySelectorAll('li')

          gsap.to(this.$refs.el.querySelector('.dropdown-icon'), { duration: 0.35, rotate: '+=180' })

          if (this.open) {
            gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -15, stagger: 0.1 })
            gsap.to(this.$refs.el, { ease: 'sine.in', duration: 0.35, delay: 0.2, height: this.height })
            this.open = false
          } else {
            this.height = this.$refs.el.offsetHeight

            gsap.set(lis, { autoAlpha: 0, x: -15 })
            gsap.to(this.$refs.el, { ease: 'sine.in', duration: 0.35, height: 'auto' })
            gsap.to(lis, { duration: 0.35, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.1 })
            this.open = true
          }
        }
      })
    },

    focus () {}
  }
}
</script>

<style lang="postcss" scoped>
  .dropdown {
    display: flex;
    flex-direction: column;
    border: 1px solid theme(colors.dark);
    height: 60px;
    border-radius: 30px;
    cursor: pointer;
    padding-top: 5px;
    padding-bottom: 5px;
    overflow-y: hidden;
    background-color: transparent;
    transition: background-color 250ms ease;
    max-width: 310px;
    margin-left: auto;

    &:hover {
      background-color: theme(colors.peachLighter);
    }

    .button {
      display: flex;
      align-items: center;
      width: 100%;
      flex-shrink: 0;
      flex-grow: 0;
    }

    .icon-wrapper {
      align-items: center;
      display: flex;
      margin-right: 15px;

      .icon {
        margin-left: 7px;
        width: 48px;
        height: 48px;
      }
    }

    .content {
      width: 100%;
      display: flex;
      line-height: 1;
      justify-content: space-between;
      padding-left: 15px;
      border-left: 1px solid;
      padding-top: 0;
      position: relative;

      .info {
        width: 100%;
        position: relative;

        .title {
          @fontsize base;
          width: 100%;
          font-weight: normal;
          padding-top: 0;
          user-select: none;
          left: 0;
        }
      }

      .dropdown-icon {
        margin-right: 20px;
        margin-top: 7px;
        transform-origin: 50% 25%;

        svg {
          path {
            fill: theme(colors.dark);
          }
        }
      }
    }

    .dropdown-content {
      padding-top: 8px;

      ul {
        li {
          line-height: 1;

          &:before {
            content: '';
            background-image: url("data:image/svg+xml,%3Csvg width='15' height='11' viewBox='0 0 15 11' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0.545998 6.3L11.76 6.3L8.106 9.918L9.15 10.962L14.28 5.832L14.28 5.364L9.15 0.234001L8.106 1.278L11.742 4.878L0.545998 4.878L0.545998 6.3Z' fill='black'/%3E%3C/svg%3E%0A");
            width: 15px;
            height: 11px;
            position: absolute;
            left: 23px;
            opacity: 0;
            transition: all 0.5s ease;
            top: 50%;
            transform: translateY(-50%);
          }

          &:hover {
            background-color: theme(colors.peach);
            &:before {
              opacity: 1;
            }
          }

          &:last-of-type {
            margin-bottom: 8px;
          }

          a, button {
            @fontsize base;
            display: block;
            padding: 14px 15px 14px calc(8px + 64px + 15px);
            font-weight: 400;
            width: 100%;
          }

          button {
            border: none;
            outline: none;
            text-align: left;
          }
        }
      }
    }
  }
</style>
