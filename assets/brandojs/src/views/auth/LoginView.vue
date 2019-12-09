<template>
  <transition name="login" @beforeAppear="beforeAppear" @appear="appear">
    <div class="login" ref="login" v-if="!token">
      <div class="brando-versioning" ref="v">
        <i class="fa fa-fw fa-adjust" /> BRANDO V &copy; 2007&mdash;2019
      </div>

      <div
        class="login-container"
        style="height: 100%;">
        <transition
          name="slide-fade-top-slow"
          appear>
          <div class="login-box" ref="loginBox">
            <div class="figure-wrapper">
              <figure v-html="$app.logo" :style="$app.logoStyle" />
            </div>
            <div
              class="login-form"
              v-if="!loading">
              <form>
                <div class="title">
                  {{ $app.name }} // ADMINISTRATION
                </div>

                <KInputEmail
                  v-model="user.email"
                  label="Login"
                  name="email"
                  placeholder="Epost"
                  @keyup.enter="login"
                  data-cy-email />
                <KInputPassword
                  v-model="user.password"
                  class="form-control"
                  label="Password"
                  name="password"
                  placeholder="Passord"
                  data-cy-password
                  @keyup.enter="login" />
              </form>
              <div>
                <ButtonPrimary
                  :dark="true"
                  @click.native.prevent="login">
                  Logg inn
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
    console.debug('created <login />')

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
      gsap.set(el, { y: 60, autoAlpha: 0, filter: 'blur(60px)' })
    },

    appear (el, done) {
      gsap.to(el, { delay: 1, y: 0, ease: 'sine.out' })
      gsap.to(el, { delay: 1, autoAlpha: 1, ease: 'sine.in' })
      gsap.to(el, { delay: 1, filter: 'blur(0px)' })
      gsap.to(this.$refs.v, { delay: 1.5, autoAlpha: 1, x: 0 })
    },

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
            this.$alerts.alertError('Feil', 'Feil brukernavn eller passord')
            break
          case 201:
            if (json) {
              this.loggingIn = true
              await onLogin(this.$apolloProvider.defaultClient)
              localStorage.setItem('token', json.jwt)

              gsap.to(this.$refs.loginBox, { autoAlpha: 0, y: -60 })
              gsap.to(this.$refs.login, { autoAlpha: 0,
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
                  this.$router.push({ name: 'dashboard' })
                } })
            }
            break
          case 423:
            this.$alerts.alertError('Feil', 'Låst konto')
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
      font-family: theme(typography.families.mono);
      transform: translateX(-15px);
    }

    .login-container {
      align-items: center;
      display: flex;
    }

    .login-box {
      @column 8/16;
      @column-offset 4/16;
      background-color: theme(colors.peach);
      border: 1px solid theme(colors.dark);
      display: flex;

      .figure-wrapper {
        @column 3/8;
        padding: 48px;
        display: flex;
        justify-content: center;
        align-items: center;

        figure {
          width: 100%;
        }
      }

      .login-form {
        @column 5:1/8;
        background-color: #ffffff;
        padding: 48px;
      }
    }
    .title {
      @space margin-bottom sm;
      font-family: theme(typography.families.mono);
      font-size: 20px;
      text-transform: uppercase;
    }
  }
</style>
