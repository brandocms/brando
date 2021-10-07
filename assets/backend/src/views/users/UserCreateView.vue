<template>
  <article v-if="user">
    <ContentHeader>
      <template #title>
        {{ $t('user.title') }}
      </template>
      <template #subtitle>
        {{ $t('user.subtitle') }}
      </template>
    </ContentHeader>
    <UserForm
      :user="user"
      :save="save" />
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
        language: 'no',
        config: {
          resetPasswordOnFirstLogin: true,
          showMutationNotifications: true
        }
      }
    }
  },

  methods: {
    async save () {
      const userParams = this.$utils.stripParams(this.user, ['__typename', 'passwordConfirm', 'id', 'lastLogin', 'deletedAt'])
      this.$utils.validateImageParams(userParams, ['avatar'])

      if (userParams.config) {
        delete userParams.config.__typename
      }

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateUser($userParams: UserParams) {
              createUser(
                userParams: $userParams
              ) {
                id
              }
            }
          `,
          variables: {
            userParams
          }
        })

        this.$toast.success({ message: this.$t('user.created') })
        this.$router.push({ name: 'users' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>

<i18n>
{
  "en": {
    "user.title": "Users",
    "user.subtitle": "New user",
    "user.created": "User created"
  },
  "no": {
    "user.title": "Brukere",
    "user.subtitle": "Ny bruker",
    "user.created": "Bruker opprettet"
  }
}
</i18n>
