<template>
  <transition
    name="slide-fade-top-slow"
    mode="out-in"
    appear>
    <li
      id="nav-profile-dropdown"
      v-click-outside="onClickOutside"
      class="dropdown">
      <a
        id="profile-dropdown-button"
        :class="(showDropdown ? 'active' : '')"
        class="d-inline-flex align-items-center dropdown-toggle user-box"
        aria-haspopup="true"
        @click.stop="toggle">
        <div class="avatar">
          <img
            :src="user.avatar ? user.avatar.medium : '/images/admin/avatar.png'"
            class="rounded-circle avatar-xs"
            alt="Avatar">
        </div>
        <div class="userinfo d-none d-sm-block">
          {{ user.full_name }}
          <span>
            administrator
          </span>
        </div>
      </a>
      <div
        v-show="showDropdown"
        :class="'dropdown-menu dropdown-menu-right has-icons' + (showDropdown ? ' show' : '')">
        <router-link
          :to="{ name: 'profile' }"
          class="dropdown-item"
          exact
          @click.native="showDropdown = false">
          <i class="fal fa-fw mr-2 fa-user" /><span>Min profil</span>
        </router-link>
        <button
          class="dropdown-item"
          @click.prevent="logout">
          <i class="fal fa-fw mr-2 fa-sign-out" /><span>Logg ut</span>
        </button>
      </div>
    </li>
  </transition>
</template>
<script>

export default {
  props: {
    user: {
      type: Object,
      default: () => {}
    }
  },

  inject: [
    'adminChannel'
  ],

  data () {
    return {
      showDropdown: false
    }
  },

  created () {
    console.debug('created <CurrentUser />')
  },

  methods: {
    onClickOutside () {
      this.showDropdown = false
    },

    toggle () {
      if (this.showDropdown) {
        this.showDropdown = false
      } else {
        this.showDropdown = true
      }
    },

    async logout () {
      let token = this.$store.getters['users/token']
      let fmData = new FormData()

      fmData.append('jwt', token)

      try {
        const response = await fetch('/admin/auth/logout', {
          method: 'post',
          body: fmData
        })

        switch (response.status) {
          case 200:
            const json = await response.json()
            if (json) {
              this.$store.commit('users/REMOVE_TOKEN')
              this.adminChannel.channel.leave()
              this.$router.push({ name: 'login' })
            }
        }
      } catch (err) {
        console.log(err)
        throw err
      }
    }
  }
}
</script>
