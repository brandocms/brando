<template>
  <article v-if="user">
    <ContentHeader>
      <template v-slot:title>
        Brukere
      </template>
      <template v-slot:subtitle>
        Ny bruker
      </template>
    </ContentHeader>
    <UserForm :user="user" :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import UserForm from './UserForm'

export default {
  components: {
    UserForm
  },

  data () {
    return {
      user: {
        language: 'nb'
      }
    }
  },

  methods: {
    async save () {
      const userParams = this.$utils.stripParams(this.user, ['__typename', 'password_confirm', 'id', 'active', 'deleted_at'])
      this.$utils.validateImageParams(userParams, ['avatar'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateUser($userParams: CreateUserParams) {
              createUser(
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
            userParams
          }
        })

        this.$toast.success({ message: 'Bruker opprettet' })
        this.$router.push({ name: 'users' })
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
    }`
  }
}
</script>

<style>

</style>
