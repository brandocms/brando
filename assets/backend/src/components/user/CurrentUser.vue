<template>
  <transition
    appear
    @beforeEnter="beforeEnter"
    @enter="enter">
    <div
      v-if="GLOBALS.me"
      ref="el"
      tabindex="0"
      :class="{ open: open }"
      class="current-user"
      data-testid="current-user"
      @click="toggle"
      @keyup.enter="toggle">
      <section class="button">
        <section class="avatar-wrapper">
          <div class="avatar">
            <img :src="GLOBALS.me.avatar ? GLOBALS.me.avatar.thumb : '/images/admin/avatar.png'" />
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              {{ GLOBALS.me.name }}
            </div>
            <div class="role">
              {{ GLOBALS.me.role }}
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
          <li>
            <router-link
              :tabindex="open ? 0 : -1"
              :to="{ name: 'profile' }">
              {{ $t('profile.edit') }}
            </router-link>
          </li>
          <li>
            <router-link
              data-testid="logout"
              :tabindex="open ? 0 : -1"
              :to="{ name: 'logout' }">
              {{ $t('logout') }}
            </router-link>
          </li>
        </ul>
      </section>
    </div>
  </transition>
</template>

<script>

import { gsap } from 'gsap'

export default {
  inject: ['GLOBALS'],
  data () {
    return {
      open: false
    }
  },

  methods: {
    beforeEnter (el) {
      if (process.env.NODE_ENV !== 'development') {
        gsap.set(el, { autoAlpha: 0, x: -15 })
      }
    },

    enter (el, done) {
      const tl = gsap.timeline({
        onComplete: done,
        paused: true
      })

      tl.to(el, { duration: 0.75, delay: 1.3, autoAlpha: 1, x: 0 })

      if (process.env.NODE_ENV !== 'development') {
        tl.play()
      }
    },

    toggle () {
      const lis = this.$refs.dropdownContent.querySelectorAll('li')

      gsap.to(this.$refs.el.querySelector('.dropdown-icon'), { duration: 0.35, rotate: '+=180' })
      if (this.open) {
        gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -8, stagger: 0.06 })
        gsap.to(this.$refs.el, { duration: 0.35, delay: 0.2, height: this.height })
        this.open = false
      } else {
        this.height = this.$refs.el.offsetHeight

        gsap.set(lis, { autoAlpha: 0, x: -8 })
        gsap.to(this.$refs.el, { duration: 0.35, height: 'auto' })
        gsap.to(lis, { duration: 0.35, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.06 })
        this.open = true
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  .current-user {
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

    &:hover {
      @color bg peachLighter;
    }

    .button {
      display: flex;
      align-items: center;
      width: 100%;
      flex-shrink: 0;
      flex-grow: 0;
    }

    .avatar-wrapper {
      align-items: center;
      display: flex;
      margin-right: 15px;

      .avatar {
        margin-left: 7px;
        width: 48px;
        height: 48px;

        img {
          user-select: none;
          border-radius: 48px;
        }
      }
    }

    .content {
      width: 100%;
      display: flex;
      line-height: 1;
      justify-content: space-between;
      padding-left: 15px;
      border-left: 1px solid;
      padding-top: 2px;

      .name {
        font-weight: normal;
        font-size: 18px;
        margin-bottom: 6px;
        user-select: none;
      }

      .role {
        @font main;
        font-size: 12px;
        opacity: 0.7;
        user-select: none;
        text-transform: uppercase;
      }

      .dropdown-icon {
        display: flex;
        align-items: center;
        margin-right: 20px;

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
            background-image: url("data:image/svg+xml,%3Csvg width='15' height='11' viewBox='0 0 15 11' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0.545998 6.3L11.76 6.3L8.106 9.918L9.15 10.962L14.28 5.832L14.28 5.364L9.15 0.234001L8.106 1.278L11.742 4.878L0.545998 4.878L0.545998 6.3Z' fill='white'/%3E%3C/svg%3E%0A");
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
            @color bg dark;
            @color fg peach;
            &:before {
              opacity: 1;
            }
          }

          &:last-of-type {
            margin-bottom: 8px;
          }

          a {
            display: block;
            padding: 14px 0 14px calc(8px + 64px + 15px);
          }
        }
      }
    }
  }
</style>

<i18n>
{
  "en": {
    "logout": "Log out",
    "profile.edit": "Edit profile"
  },

  "no": {
    "logout": "Logg ut",
    "profile.edit": "Endre profil"
  }
}
</i18n>
