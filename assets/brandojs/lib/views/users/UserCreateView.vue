<template>
  <transition
    name="fade"
    mode="out-in"
    appear>
    <div class="users-create">
      <ValidationObserver
        ref="observer">
        <div
          id="content"
          class="container">
          <div class="cards">
            <div class="card w-50">
              <div class="card-header">
                <h5 class="section mb-0">
                  Ny bruker
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
                  label="Rolle" />

                <KInputSelect
                  v-model="user.language"
                  rules="required"
                  :value="user.language"
                  :options="[
                    { name: 'Norsk', value: 'nb' },
                    { name: 'Engelsk', value: 'en' }
                  ]"
                  name="user[language]"
                  label="Språk" />

                <KInput
                  v-model="user.full_name"
                  rules="required"
                  :value="user.full_name"
                  name="user[full_name]"
                  label="Navn"
                  placeholder="Navn" />

                <KInputEmail
                  v-model="user.email"
                  rules="required"
                  :value="user.email"
                  name="user[email]"
                  label="Epost"
                  placeholder="Epost" />

                <KInputPassword
                  ref="password"
                  v-model="user.password"
                  rules="min:6|required|confirmed:user[password_confirm]"
                  :value="user.password"
                  name="user[password]"
                  label="Passord"
                  placeholder="Passord" />

                <KInputPassword
                  v-model="user.password_confirm"
                  rules="required"
                  :value="user.password_confirm"
                  name="user[password_confirm]"
                  label="Bekreft passord"
                  placeholder="Bekreft passord" />

                <button
                  class="btn btn-secondary mt-4"
                  @click.prevent="validate">
                  Lagre ny bruker
                </button>
              </div>
            </div>
          </div>
        </div>
      </ValidationObserver>
    </div>
  </transition>
</template>

<script>
import { mapActions } from 'vuex'
import { alertError } from '../../utils/alerts'

export default {
  data () {
    return {
      user: {
        full_name: '',
        email: '',
        language: 'nb',
        role: 'user',
        password: '',
        password_confirm: ''
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    console.debug('created <UsersCreate />')
  },

  methods: {
    async save () {
      try {
        await this.storeUser(this.user)
        this.$toast.success({ message: 'La til ny bruker' })
        this.$router.push({ name: 'users' })
      } catch (err) {
        throw err
      }
    },

    async validate () {
      const isValid = await this.$refs.observer.validate()
      if (!isValid) {
        alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
        this.loading = false
        return
      }
      this.save()
    },
    ...mapActions('users', [
      'storeUser'
    ])
  }
}
</script>
