<template>
  <dl ref="el">
    <template v-if="item.items && $can('view', {...item, '__typename': 'MenuItem' })">
      <dt
        @mouseover="$emit('hover', $event)"
        @click="toggle">
        {{ item.name }}
      </dt>
      <dd
        v-if="item.items"
        ref="dd">
        <ul>
          <li
            v-for="subitem in item.items"
            v-if="$can('view', {...subitem, '__typename': 'MenuItem' })"
            :key="subitem.text">
            <router-link
              :to="subitem.to">
              {{ subitem.text }}
            </router-link>
          </li>
        </ul>
      </dd>
    </template>
    <template v-else-if="item && item.to && $can('view', {...item, '__typename': 'MenuItem' })">
      <dt
        @mouseover="$emit('hover', $event)">
        <router-link
          exact
          :to="item.to">
          {{ item.name }}
        </router-link>
      </dt>
    </template>
  </dl>
</template>

<script>

import { gsap } from 'gsap'

export default {
  props: {
    item: {
      type: Object,
      required: true
    }
  },
  data () {
    return {
      open: false
    }
  },

  methods: {
    toggle () {
      const lis = this.$refs.dd.querySelectorAll('li')

      if (this.open) {
        gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -15, stagger: 0.1 })
        gsap.to(this.$refs.el, { duration: 0.35, delay: 0.2, height: this.height })
        this.open = false
      } else {
        this.height = this.$refs.el.offsetHeight
        gsap.set(this.$refs.el, { height: this.height })
        gsap.set(lis, { autoAlpha: 0, x: -15 })
        gsap.set(this.$refs.dd, { opacity: 1, display: 'block' })
        gsap.to(this.$refs.el, { duration: 0.35, height: 'auto' })
        gsap.to(lis, { duration: 0.35, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.1 })
        this.open = true
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  dl {
    padding-bottom: 0;

    &:empty {
      display: none;
    }

    dt {
      @fontsize nav.mainItem;
      color: theme(colors.dark);
      cursor: pointer;
      user-select: none;
      font-weight: 200;

      a {
        font-weight: 200;
        display: block;

        &:before {
          content: '';
          position: absolute;
          background-image: url("data:image/svg+xml,%3Csvg width='18' height='18' viewBox='0 0 18 18' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='9' cy='9' r='9' fill='%230047FF'/%3E%3C/svg%3E%0A");
          width: 18px;
          height: 18px;
          opacity: 0;
          margin-top: 10px;
          margin-left: -34px;
          transition: opacity 1s ease;
        }

        &.active {
          font-weight: 400;
          &:before {
            opacity: 1;
          }
        }
      }
    }

    dd {
      @fontsize nav.mainItem;
      opacity: 0;
      display: none;
      margin-left: 30px;
      color: theme(colors.dark);

      ul {
        li {
          &:before {
            content: '';
            background-image: url("data:image/svg+xml,%3Csvg width='15' height='11' viewBox='0 0 15 11' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0.545998 6.3L11.76 6.3L8.106 9.918L9.15 10.962L14.28 5.832L14.28 5.364L9.15 0.234001L8.106 1.278L11.742 4.878L0.545998 4.878L0.545998 6.3Z' fill='black'/%3E%3C/svg%3E%0A");
            width: 15px;
            height: 11px;
            position: absolute;
            left: -30px;
            opacity: 0;
            transition: all 0.5s ease;
            margin-top: 13px;
          }

          &:hover {
            &:before {
              opacity: 0.5;
            }
          }

          a {
            @fontsize 20px;
            display: block;
            font-weight: 200;

            &.active {
              font-weight: 400;
            }
          }
        }
      }
    }
  }
</style>
