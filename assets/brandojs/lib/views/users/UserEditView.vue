<template>
  <transition
    name="fade"
    mode="out-in"
    appear>
    <div class="users-edit">
      <div
        id="content"
        class="container">
        <div class="cards">
          <div class="card w-50">
            <div class="card-header">
              <h5 class="section mb-0">
                Endre bruker
              </h5>
            </div>
            <div class="card-body">
              <KInputRadios
                v-model="user.role"
                rules="required"
                :value="user.role"
                :options="[
                  { name: 'Superbruker', value: 'superuser' },
                  { name: 'Admin', value: 'admin' },
                  { name: 'Stab', value: 'staff' }
                ]"
                name="user[role]"
                label="Rolle"
                data-vv-name="user[role]"
                data-vv-value-path="innerValue" />

              <KInputSelect
                v-model="user.language"
                rules="required"
                :value="user.language"
                :options="[
                  { name: 'Norsk', value: 'nb' },
                  { name: 'Engelsk', value: 'en' }
                ]"
                name="user[language]"
                label="Språk"
                data-vv-name="user[language]"
                data-vv-value-path="innerValue" />

              <KInput
                v-model="user.full_name"
                rules="required"
                :value="user.full_name"
                name="user[full_name]"
                label="Navn"
                placeholder="Navn"
                data-vv-name="user[full_name]"
                data-vv-value-path="innerValue" />

              <KInputEmail
                v-model="user.email"
                rules="required"
                :value="user.email"
                name="user[email]"
                label="Epost"
                placeholder="Epost"
                data-vv-name="user[email]"
                data-vv-value-path="innerValue" />
              <KInputPassword
                ref="password"
                v-model="user.password"
                rules="min:6|confirmed:profile[password_confirm]"
                :value="user.password"
                name="user[password]"
                label="Passord"
                placeholder="Passord"
                data-vv-name="user[password]"
                data-vv-value-path="innerValue" />
              <KInputPassword
                v-model="user.password_confirm"
                :value="user.password_confirm"
                name="user[password_confirm]"
                label="Bekreft passord"
                placeholder="Bekreft passord"
                data-vv-name="user[password_confirm]"
                data-vv-value-path="innerValue" />

              <button
                class="btn btn-secondary mt-4"
                @click.prevent="validateBeforeSubmit">
                Oppdatér bruker
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </transition>
</template>

<script>
import { mapActions } from 'vuex'
import { userAPI } from '../../api/user'
import { alertError } from '../../utils/alerts'
import { pick } from '../../utils'

export default {

  props: {
    userId: {
      type: String,
      required: true,
      default: null
    }
  },
  data () {
    return {
      user: {}
    }
  },

  inject: [
    'adminChannel'
  ],

  async created () {
    console.debug('created <UsersEdit />')
    try {
      const user = await userAPI.getUser(this.userId)
      this.user = { ...user }
    } catch (err) {
      console.log(err)
    }
  },

  methods: {
    async submitForm () {
      const params = pick(
        this.user,
        'full_name', 'email', 'password', 'role', 'language', 'username'
      )
      try {
        await this.updateUser({ userId: this.user.id, userParams: params })
        this.$toast.success({ message: 'Bruker oppdatert' })
        this.$router.push({ name: 'users' })
      } catch (err) {
        throw err
      }
    },

    validateBeforeSubmit (e) {
      this.loading = true
      this.$validator.validateAll().then(result => {
        if (!result) {
          alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
          this.loading = false
          return
        }
        this.submitForm()
        this.loading = false
      })
    },
    ...mapActions('users', [
      'storeUser',
      'updateUser'
    ])
  }
}
</script>
