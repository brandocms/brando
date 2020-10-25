<template>
  <article v-if="identity">
    <ContentHeader>
      <template v-slot:title>
        {{ $t('title') }}
      </template>
      <template v-slot:subtitle>
        {{ identity.name }}
      </template>
      <template v-slot:help>
      </template>
    </ContentHeader>
    <slot></slot>
  </article>
</template>

<script>

import GET_IDENTITY from 'brandojs/src/gql/identity/IDENTITY_QUERY.graphql'

export default {
  apollo: {
    identity: {
      query: GET_IDENTITY
    }
  }
}

</script>

<i18n>
  {
    "en": {
      "title": "Admin area"
    },
    "no": {
      "title": "Administrasjonsområde"
    }
  }
</i18n>
