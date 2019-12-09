<template>
  <article v-if="user">
    <ContentHeader>
      <template v-slot:title>
        Din brukerprofil
      </template>
      <template v-slot:subtitle>
        Administrasjon av brukerinfo
      </template>
    </ContentHeader>
    <KForm
      :back="{ name: 'users' }"
      @save="save">
      <section class="row">
        <div class="half">
          <KInput
            v-model="user.full_name"
            label="Navn"
            helpText="navn som brukes når du er artikkelforfatter"
            rules="required"
            placeholder="Navn Navnesen"
            name="user[full_name]" />
          <KInputEmail
            v-model="user.email"
            label="Epost"
            helpText="brukes til innlogging og notifikasjoner"
            rules="required|email"
            placeholder="min@epost.no"
            name="user[email]" />
          <KInputRadios
            v-model="user.role"
            rules="required"
            :options="[
              { name: 'Superbruker', value: 'superuser' },
              { name: 'Admin', value: 'admin' },
              { name: 'Stab', value: 'staff' }
            ]"
            name="user[role]"
            label="Rolle" />
          <KInputPassword
            v-model="user.password"
            rules="min:6|confirmed:user[password_confirm]"
            name="user[password]"
            label="Passord"
            placeholder="Passord"
          />
          <KInputPassword
            v-model="user.password_confirm"
            name="user[password_confirm]"
            label="Bekreft passord"
            placeholder="Bekreft passord"
          />
        </div>
        <div class="half">
          <KInputImage
            v-model="user.avatar"
            name="user[avatar]"
            label="Profilbilde"
            helpText="Klikk på bildet for å sette fokuspunkt."
          />
        </div>
      </section>
    </KForm>
  </article>
</template>

<script>

import gql from 'graphql-tag'

export default {
  data () {
    return {
    }
  },

  methods: {
    async save () {
      const userParams = this.$utils.stripParams(this.user, ['__typename', 'password_confirm', 'id', 'active', 'deleted_at'])
      this.$utils.validateImageParams(userParams, ['avatar'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateUser($userId: ID!, $userParams: UpdateUserParams) {
              updateUser(
                userId: $userId,
                userParams: $userParams
              ) {
                id
                language
                full_name
                email
                avatar {
                  focal
                  thumb: url(size: "xlarge")
                }
                role
              }
            }
          `,
          variables: {
            userParams,
            userId: this.me.id
          }
        })

        this.$toast.success({ message: 'Profil oppdatert' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    me: gql`query Me {
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
    }`,

    user: {
      query: gql`
        query User ($userId: ID!) {
          user (userId: $userId) {
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
            deleted_at
          }
        }
      `,
      variables () {
        return {
          userId: this.me.id
        }
      },

      skip () {
        return !this.me
      }
    }
  }
}
</script>

<style>

</style>
