<template>
  <article v-if="user">
    <ContentHeader>
      <template #title>
        {{ $t('users') }}
      </template>
      <template #subtitle>
        {{ $t('new-password') }}
      </template>
    </ContentHeader>
    <div class="notice">
      {{ $t('password-notice') }}
    </div>
    <UserPasswordForm
      :user="user"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import UserPasswordForm from './UserPasswordForm'
import GET_ME from '../../gql/users/ME_QUERY.graphql'
import GET_USER from '../../gql/users/USER_QUERY.graphql'

export default {
  components: {
    UserPasswordForm
  },

  data () {
    return {
    }
  },

  methods: {
    async save (setLoader) {
      setLoader(true)

      const userParams = this.$utils.stripParams(this.user, ['__typename', 'passwordConfirm', 'id', 'active', 'deletedAt', 'lastLogin'])
      this.$utils.validateImageParams(userParams, ['avatar'])

      if (userParams.config) {
        delete userParams.config.__typename
      }

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateUser($userId: ID!, $userParams: UserParams) {
              updateUser(
                userId: $userId,
                userParams: $userParams
              ) {
                id
              }
            }
          `,
          variables: {
            userParams,
            userId: this.me.id
          }
        })

        setLoader(false)
        this.$toast.success({ message: this.$t('password-updated') })
        this.$router.push({ name: 'dashboard' })
      } catch (err) {
        this.$utils.showError(err)
        setLoader(false)
      }
    }
  },

  apollo: {
    me: GET_ME,

    user: {
      query: GET_USER,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          matches: { id: this.me.id }
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
  .notice {
    margin-bottom: 2rem;
  }
</style>

<i18n>
  {
    "en": {
      "users": "Users",
      "new-password": "New password",
      "password-updated": "Password updated",
      "password-notice": "As this is your first time logged in, please set your own secure password"
    },
    "no": {
      "users": "Brukere",
      "new-password": "Nytt passord",
      "password-updated": "Passord oppdatert",
      "password-notice": "Vi anbefaler deg å sette ditt eget, sikre passord ved første innlogging."
    }
  }
</i18n>
