<template>
  <transition name="login">
    <div class="login">
      <div
        :class="{'logging-in': loggingIn}"
        class="container-fluid fixed-full-content">
        <div class="twined-versioning">
          <i class="fa fa-fw fa-adjust" /> KURTZ V &copy; TWINED 2007 - 2017
        </div>
        <div
          class="d-flex justify-content-center flex-wrap align-items-center text-center"
          style="height: 100%;">
          <transition
            name="slide-fade-top-slow"
            appear>
            <div class="login-box">
              <img
                src="/images/logo.svg"
                class="avatar-sm mb-5">
              <div v-if="!loading">
                <div class="text-center">
                  <form>
                    <input
                      v-model="user.email"
                      class="form-control text-center mb-4"
                      name="email"
                      type="email"
                      placeholder="Epost"
                      data-cy-email>
                    <input
                      v-model="user.password"
                      class="form-control text-center mb-5"
                      name="password"
                      type="password"
                      placeholder="Passord"
                      data-cy-password
                      @keyup.13="login">
                  </form>
                </div>
                <div>
                  <button
                    class="btn btn-outline-dark"
                    @click.prevent="login">
                    Logg inn
                  </button>
                </div>
              </div>
            </div>
          </transition>
        </div>
      </div>
    </div>
  </transition>
</template>

<script>

import { alertError } from '../../utils/alerts'
import { mapGetters } from 'vuex'

export default {

  data () {
    return {
      loggingIn: false,
      user: {
        email: '',
        password: ''
      },
      kurtzVersion: '',
      loading: 0
    }
  },

  computed: {
    ...mapGetters('users', ['me'])
  },

  created () {
    this.loading++
    console.debug('created <login />')
    let token = this.$store.getters['users/token']

    if (token && this.checkExpired()) {
      //
    } else {
      if (token && this.me) {
        this.$router.push({ name: 'dashboard' })
      }
    }
  },

  mounted () {
    this.loading--
  },

  methods: {
    async login () {
      const fmData = new FormData()

      fmData.append('email', this.user.email)
      fmData.append('password', this.user.password)

      try {
        const response = await fetch('/admin/auth/login', {
          method: 'post',
          body: fmData
        })

        const json = await response.json()

        switch (response.status) {
          case 401:
            alertError('Feil', 'Feil brukernavn eller passord')
            break
          case 201:
            if (json) {
              this.loggingIn = true
              setTimeout(async () => {
                await this.$store.commit('users/STORE_TOKEN', json.jwt)
                this.$router.push({ name: 'dashboard' })
              }, 1500)
            }
            break
          case 423:
            alertError('Feil', 'Låst konto')
            break
        }
      } catch (err) {
        throw err
      }
    },

    checkExpired () {
      var queryDict = {}
      document.location.search.substr(1).split('&').forEach(function (item) {
        queryDict[item.split('=')[0]] = item.split('=')[1]
      })

      if (queryDict['expired']) {
        return true
      }
      return false
    }
  }
}
</script>
