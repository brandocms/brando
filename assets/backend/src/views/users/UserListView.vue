<template>
  <div class="user-list">
    <ContentHeader>
      <template #title>
        {{ $t('user.title') }}
      </template>
      <template #subtitle>
        {{ $t('user.subtitle') }}
      </template>
      <template #help>
        <div class="float-right">
          <ButtonPrimary
            :to="{ name: 'users-new' }">
            + {{ $t('user.new') }}
          </ButtonPrimary>
        </div>
      </template>
    </ContentHeader>

    <ContentList
      v-if="users"
      :selectable="false"
      :tools="false"
      :entries="users">
      <template #header>
        <div class="col-2"></div>
        <div class="col-13">
          Info
        </div>
        <div class="col-1"></div>
      </template>
      <template #row="{ entry }">
        <div class="col-2">
          <div class="thumb">
            <img :src="entry.avatar ? entry.avatar.thumb : '/images/admin/avatar.png'" />
          </div>
        </div>
        <div class="col-13">
          <router-link
            v-if="$can('manage', entry)"
            :to="{ name: 'users-edit', params: { userId: entry.id } }"
            class="link name-link"
            :class="{ inactive: !entry.active }">
            {{ entry.name }}
          </router-link>
          <span v-else>
            {{ entry.name }}
          </span>
          <br>
          <small>
            {{ entry.email }}
          </small>
          <br>
          <div class="badge">
            {{ entry.role }}
          </div>
        </div>
        <div class="col-1">
          <CircleDropdown v-if="$can('manage', entry)">
            <li>
              <router-link
                :to="{ name: 'users-edit', params: { userId: entry.id } }">
                {{ $t('user.edit') }}
              </router-link>
              <button
                v-if="entry.active"
                @click="toggleActive(entry, false)">
                {{ $t('user.deactivate') }}
              </button>
              <button
                v-else
                @click="toggleActive(entry, true)">
                {{ $t('user.activate') }}
              </button>
            </li>
          </CircleDropdown>
        </div>
      </template>
    </ContentList>
  </div>
</template>

<script>

import gql from 'graphql-tag'
import GET_USERS from '../../gql/users/USERS_QUERY.graphql'

export default {
  data () {
    return {
    }
  },

  methods: {
    async toggleActive (user, active) {
      if (user.role === 'superuser') {
        this.$alerts.alertError(this.$t('error'), this.$t('superuser-cannot-be-deactivated'))
        return
      }
      const userParams = { active }
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateUser($userId: ID!, $userParams: UserParams) {
              updateUser(
                userId: $userId,
                userParams: $userParams
              ) {
                id
                active
              }
            }
          `,
          variables: {
            userParams,
            userId: user.id
          }
        })

        if (active) {
          this.$toast.success({ message: this.$t('user.activated') })
        } else {
          this.$toast.success({ message: this.$t('user.deactivated') })
        }

      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    users: {
      query: GET_USERS
    }
  }
}
</script>

<i18n>
{
  "en": {
    "error": "Error",
    "superuser-cannot-be-deactivated": "Superuser cannot be deactivated",
    "user.title": "Users",
    "user.subtitle": "Administrate users",
    "user.new": "Create user",
    "user.edit": "Edit user",
    "user.activate": "Activate user",
    "user.deactivate": "Deactivate user",
    "user.activated": "User activated",
    "user.deactivated": "User deactivated"
  },
  "no": {
    "error": "Feil",
    "superuser-cannot-be-deactivated": "Superbruker kan ikke deaktiveres",
    "user.title": "Brukere",
    "user.subtitle": "Administrasjon av brukere.",
    "user.new": "Ny bruker",
    "user.edit": "Rediger bruker",
    "user.activate": "Aktivér bruker",
    "user.deactivate": "Deaktivér bruker",
    "user.activated": "Bruker aktivért",
    "user.deactivated": "Bruker deaktivért"
  }
}
</i18n>

<style lang="postcss" scoped>
  .name-link {
    &.inactive {
      text-decoration: line-through;
      opacity: 0.6;
    }
  }
</style>
