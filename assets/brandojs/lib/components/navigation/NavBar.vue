<template>
  <header>
    <transition
      name="slide-fade-top-slow"
      appear>
      <div
        v-if="lobbyPresences !== {}"
        class="presences">
        <span class="text-uppercase text-xs pr-2">online &rarr; </span>
        <transition-group
          class="d-inline-flex justify-content-center"
          tag="div"
          name="fade">
          <div
            v-for="(p, id) in lobbyPresences"
            :key="id + 1"
            class="user-presence">
            <div
              v-b-popover.hover.right="userById(id).full_name"
              class="avatar">
              <img
                :src="userById(id).avatar ? userById(id).avatar.thumb : '/images/admin/avatar.png'"
                class="rounded-circle avatar-xxs">
            </div>
          </div>
        </transition-group>
      </div>
    </transition>
    <section class="container">
      <transition
        name="slide-fade-top-slow"
        appear>
        <nav class="navbar navbar-toggleable-xxl">
          <Hamburger />
          <div class="logo-wrapper mr-auto">
            {{ siteName }}
          </div>

          <div
            id="navbar-collapse"
            class="align-items-center">
            <ul class="nav navbar-right ml-auto">
              <CurrentUser :user="me" />
            </ul>
          </div>
        </nav>
      </transition>
    </section>
  </header>
</template>

<script>

import { mapGetters } from 'vuex'
import Hamburger from './Hamburger.vue'
import CurrentUser from '../CurrentUser.vue'

export default {
  components: {
    CurrentUser,
    Hamburger
  },

  computed: {
    ...mapGetters('users', [
      'me',
      'userById',
      'lobbyPresences'
    ]),
    ...mapGetters('config', [
      'siteName'
    ])
  }
}
</script>
