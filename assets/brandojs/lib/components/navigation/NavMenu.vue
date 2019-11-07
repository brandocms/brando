<template>
  <div
    v-click-outside="onClickOutside"
    class="menu-backdrop">
    <div class="menu-content d-flex flex-column align-items-center">
      <div class="top">
        <div class="avatar mx-auto">
          <img
            :src="me.avatar ? me.avatar.medium : '/images/admin/avatar.png'"
            alt="Profilbilde"
            class="rounded-circle img-fluid">
        </div>
        <div class="info text-center mb-3 text-white">
          <h6>
            <router-link
              v-if="me"
              :to="{ name: 'profile' }"
              exact
              @click.stop.native="close">
              {{ me.full_name }}
            </router-link>
          </h6>
        </div>
      </div>

      <div class="menu-line-main">
        <router-link
          :to="{ name: 'dashboard' }"
          exact
          @click.stop.native="close">
          <span class="nav-icon">
            <i class="fal fa-tachometer-alt" />
          </span>
          Mitt dashboard
        </router-link>
      </div>

      <NavMenuItem
        text="Konfigurasjon"
        icon="fal fa-fw fa-cog"
        @expanding="expanding">
        <router-link
          key="1"
          :to="{ name: 'config' }"
          data-index="1"
          exact
          @click.native="close">
          Identitet
        </router-link>
      </NavMenuItem>

      <NavMenuItem
        text="Brukere"
        icon="fal fa-fw fa-user-circle"
        @expanding="expanding">
        <router-link
          key="1"
          :to="{ name: 'users' }"
          data-index="1"
          exact
          @click.native="close">
          Oversikt
        </router-link>
        <router-link
          key="2"
          :to="{ name: 'user-create' }"
          data-index="2"
          @click.native="close">
          Opprett ny bruker
        </router-link>
      </NavMenuItem>

      <NavMenuItem
        text="Bilder"
        icon="fal fa-fw fa-image"
        @expanding="expanding">
        <router-link
          key="1"
          :to="{ name: 'images' }"
          data-index="1"
          exact
          @click.native="close">
          Oversikt
        </router-link>
      </NavMenuItem>

      <NavMenuItem
        v-if="showPages"
        text="Sider"
        icon="fal fa-fw fa-file-alt"
        @expanding="expanding">
        <router-link
          v-if="settings.pages"
          key="1"
          :to="{ name: 'pages' }"
          data-index="1"
          exact
          @click.native="close">
          Oversikt
        </router-link>
        <router-link
          v-if="settings.pages"
          key="2"
          :to="{ name: 'page-create' }"
          data-index="2"
          exact
          @click.native="close">
          Opprett ny side
        </router-link>
      </NavMenuItem>

      <NavMenuItem
        v-if="['admin'].includes(me.role)"
        text="Maler"
        icon="fal fa-fw fa-map"
        @expanding="expanding">
        <router-link
          key="1"
          :to="{ name: 'templates' }"
          data-index="1"
          exact
          @click.native="close">
          Editor (avansert)
        </router-link>
      </NavMenuItem>

      <template v-for="(entry, idx) in entries">
        <NavMenuItem
          :key="idx"
          :text="entry.text"
          :icon="entry.icon"
          @expanding="expanding">
          <router-link
            v-for="(child, cIdx) in entry.children"
            :key="cIdx"
            :to="child.to"
            exact
            @click.native="close">
            {{ child.text }}
          </router-link>
        </NavMenuItem>
      </template>
    </div>
  </div>
</template>

<script>

import { mapGetters } from 'vuex'
import NavMenuItem from './NavMenuItem.vue'

export default {
  components: {
    NavMenuItem
  },

  computed: {
    showPages () {
      if (!this.settings.pages && !this.settings.pageFragments) {
        return false
      }
      return true
    },

    ...mapGetters('menu', [
      'entries', 'status'
    ]),
    ...mapGetters('users', [
      'me'
    ]),
    ...mapGetters('config', [
      'settings'
    ])
  },

  created () {
    console.debug('created <NavMenu />')
  },

  methods: {
    onClickOutside () {
      if (this.status) {
        this.hide()
      }
    },

    expanding (a) {
      this.closeSubs()
    },

    closeSubs () {
      let subs = document.getElementsByClassName('menu-line-wrapper open')
      for (let sub of Array.from(subs)) {
        sub.classList.remove('open')
      }
    },

    hide () {
      this.$store.commit('menu/TOGGLE_MENU')
    },

    close (e) {
      this.hide()

      // if the link clicked is not in a sub-nav, we close all the other subnavs!
      if (e.currentTarget.parentNode.classList.contains('menu-line-main')) {
        this.closeSubs()
      }
    }
  }
}
</script>
