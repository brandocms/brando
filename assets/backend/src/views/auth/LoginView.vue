<template>
  <transition
    name="login"
    @beforeAppear="beforeAppear"
    @appear="appear">
    <div
      v-if="!token"
      ref="login"
      class="login">
      <div
        ref="v"
        class="brando-versioning">
        <i class="fa fa-fw fa-adjust" /> BRANDO &copy; {{ new Date().getFullYear() }}
      </div>

      <div
        class="login-container"
        style="height: 100%;">
        <transition
          name="slide-fade-top-slow"
          appear>
          <div
            ref="loginBox"
            class="login-box">
            <div class="figure-wrapper">
              <figure
                :style="$app.logoStyle"
                v-html="$app.logo" />
            </div>
            <div
              v-if="!loading"
              class="login-form">
              <form>
                <div class="title">
                  {{ $app.name }}
                </div>

                <KInputEmail
                  v-model="user.email"
                  label="Login"
                  name="email"
                  placeholder="Epost"
                  data-testid="email"
                  @keyup.native.enter="login" />
                <KInputPassword
                  v-model="user.password"
                  class="form-control"
                  label="Password"
                  name="password"
                  placeholder="Passord"
                  data-testid="password"
                  @keyup.native.enter="login" />
              </form>
              <div>
                <ButtonPrimary
                  :dark="true"
                  data-testid="login-button"
                  @click.native.prevent="login">
                  Login &rarr;
                </ButtonPrimary>
              </div>
            </div>
          </div>
        </transition>
      </div>
    </div>
  </transition>
</template>

<script>

import { gsap } from 'gsap'
import gql from 'graphql-tag'
import { onLogin } from '../../vue-apollo'

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

  created () {
    this.loading++

    if (this.token && this.checkExpired()) {
      //
    } else {
      if (this.token && this.me) {
        this.$router.push({ name: 'dashboard' })
      }
    }
  },

  mounted () {
    this.loading--
  },

  methods: {
    beforeAppear (el) {
      gsap.set(el, { y: 60, autoAlpha: 0 })
    },

    appear (el, done) {
      gsap.to(el, { delay: 1, y: 0, ease: 'sine.out' })
      gsap.to(el, { delay: 1, autoAlpha: 1, ease: 'sine.in' })
      gsap.to(this.$refs.v, { delay: 1.5, autoAlpha: 1, x: 0 })
    },

    async login () {
      const fmData = new FormData()

      fmData.append('email', this.user.email)
      fmData.append('password', this.user.password)

      const response = await fetch('/admin/auth/login', {
        method: 'post',
        body: fmData
      })

      const json = await response.json()

      switch (response.status) {
        case 401:
          this.$alerts.alertError('Feil', 'Feil brukernavn eller passord')
          break
        case 201:
          if (json) {
            this.loggingIn = true
            await onLogin(this.$apolloProvider.defaultClient)
            this.$ability.update(json.rules)
            localStorage.setItem('token', json.jwt)

            gsap.to(this.$refs.loginBox, { autoAlpha: 0, y: -60 })
            gsap.to(this.$refs.login, {
              autoAlpha: 0,
              delay: 0.5,
              onComplete: () => {
                this.$apollo.mutate({
                  mutation: gql`
                    mutation setToken ($value: String!) {
                      tokenSet (value: $value) @client
                    }
                  `,
                  variables: {
                    value: localStorage.getItem('token')
                  }
                })
                this.$root.ready = true
                if (json.config && json.config.reset_password_on_first_login && !json.last_login) {
                  this.$router.push({ name: 'users-new-password' })
                } else {
                  this.$router.push({ name: 'dashboard' })
                }
              }
            })
          }
          break
        case 423:
          this.$alerts.alertError('Feil', 'Låst konto')
          break
      }
    },

    checkExpired () {
      var queryDict = {}
      document.location.search.substr(1).split('&').forEach(function (item) {
        queryDict[item.split('=')[0]] = item.split('=')[1]
      })

      if (queryDict.expired) {
        return true
      }
      return false
    }
  },

  apollo: {
    token: gql`
      query getToken {
        token @client
      }
    `
  }
}
</script>

<style lang="postcss" scoped>
  .login {
    @container;
    height: 100vh;
    position: relative;
    background-color: theme(colors.peachLighter);

    .brando-versioning {
      @fontsize xs;
      opacity: 0;
      position: absolute;
      bottom: 0;
      left: 0;
      font-family: theme(typography.families.mono);
    }

    .login-container {
      align-items: center;
      display: flex;
    }

    .login-box {
      @column 10/16;
      @column-offset 4/16;
      max-width: 920px !important;
      background-color: theme(colors.peach);
      box-shadow:
        0 2.8px 2.2px rgba(0, 0, 0, 0.02),
        0 6.7px 5.3px rgba(0, 0, 0, 0.028),
        0 12.5px 10px rgba(0, 0, 0, 0.035),
        0 22.3px 17.9px rgba(0, 0, 0, 0.042),
        0 41.8px 33.4px rgba(0, 0, 0, 0.05),
        0 100px 80px rgba(0, 0, 0, 0.07);

      display: flex;

      .figure-wrapper {
        @column 5/10;
        padding: 75px;
        display: flex;
        justify-content: center;
        align-items: center;

        figure {
          width: 100%;
        }
      }

      .login-form {
        @column 5:1/10;
        background-color: #ffffff;
        padding: 48px;
      }
    }
    .title {
      @space margin-bottom sm;
      font-family: theme(typography.families.mono);
      font-size: 20px;
      /* text-transform: uppercase; */
    }
  }
</style>
