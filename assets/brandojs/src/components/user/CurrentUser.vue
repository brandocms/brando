<template>
  <transition
    @beforeEnter="beforeEnter"
    @enter="enter"
    appear>
    <div
      v-if="!$apollo.queries.me.loading"
      tabindex="0"
      :class="{ open: open }"
      class="current-user"
      @click="toggle"
      @keyup.enter="toggle"
      @focus="focus"
      ref="el">
      <section class="button">
        <section class="avatar-wrapper">
          <div class="avatar">
            <img :src="me.avatar ? me.avatar.thumb : '/images/admin/avatar.png'" />
          </div>
        </section>
        <section class="content">
          <div class="info">
            <div class="name">
              {{ me.full_name }}
            </div>
            <div class="role">
              {{ me.role }}
            </div>
          </div>
          <div class="dropdown-icon">
            <svg width="13" height="10" viewBox="0 0 13 10" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M6.5 10L0.00480841 0.624999L12.9952 0.624998L6.5 10Z" fill="black"/>
            </svg>
          </div>
        </section>
      </section>
      <section class="dropdown-content" ref="dropdownContent">
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
import gql from 'graphql-tag'

export default {
  data () {
    return {
      open: false
    }
  },

  methods: {
    beforeEnter (el) {
      gsap.set(el, { autoAlpha: 0, x: -15 })
    },

    enter (el, done) {
      const tl = gsap.timeline({
        onComplete: done
      })

      tl.to(el, { duration: 0.75, delay: 1.3, autoAlpha: 1, x: 0 })
    },

    toggle () {
      let lis = this.$refs.dropdownContent.querySelectorAll('li')

      gsap.to(this.$refs.el.querySelector('.dropdown-icon'), { duration: 0.35, rotate: '+=180' })
      if (this.open) {
        gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -15, stagger: 0.1 })
        gsap.to(this.$refs.el, { duration: 0.35, delay: 0.2, height: this.height })
        this.open = false
      } else {
        this.height = this.$refs.el.offsetHeight

        gsap.set(lis, { autoAlpha: 0, x: -15 })
        gsap.to(this.$refs.el, { duration: 0.35, height: 'auto' })
        gsap.to(lis, { duration: 0.35, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.1 })
        this.open = true
      }
    },

    focus () {
      console.log('focus!')
    }
  },

  apollo: {
    // Simple query that will update the 'hello' vue property
    me: gql`
      query Me {
        me {
          id
          full_name
          email
          avatar {
            focal
            thumb: url(size: "xlarge")
          }
          role
          language
          active
        }
      }
    `
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
    margin-left: -8px;
    margin-right: -8px;
    cursor: pointer;
    padding-top: 5px;
    padding-bottom: 5px;
    overflow-y: hidden;
    background-color: transparent;
    transition: background-color 250ms ease;

    &.open {
      /* height: auto; */
      /* border-radius: 0; */
    }

    &:hover {
      background-color: #ffffff;
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
        user-select: none;
      }

      .role {
        font-family: 'Maison Neue', monospace;
        font-size: 12px;
        opacity: 70%;
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

          a {
            display: block;
            padding: 14px 0 8px calc(8px + 64px + 15px);
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

  "nb": {
    "logout": "Logg ut",
    "profile.edit": "Endre profil"
  }
}
</i18n>
