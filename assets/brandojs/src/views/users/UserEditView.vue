<template>
  <article v-if="user">
    <ContentHeader>
      <template v-slot:title>
        Brukere
      </template>
      <template v-slot:subtitle>
        Endre brukerinfo
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

  props: {
    userId: {
      type: [String, Number],
      required: true
    }
  },

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
            userId: this.userId
          }
        })

        this.$toast.success({ message: 'Bruker oppdatert' })
        this.$router.push({ name: 'users' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
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
          }
        }
      `,
      variables () {
        return {
          userId: this.userId
        }
      },

      skip () {
        return !this.userId
      }
    }
  }
}
</script>

<style>

</style>
