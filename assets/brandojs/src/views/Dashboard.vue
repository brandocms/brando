<template>
  <article v-if="identity">
    <ContentHeader>
      <template v-slot:title>
        Administrasjonsområde
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

import gql from 'graphql-tag'

export default {
  apollo: {
    identity: {
      query: gql`
        query Identity {
          identity {
            id
            type
            name
            alternate_name
            email
            phone
            address
            zipcode
            city
            country
            description
            title_prefix
            title
            title_postfix

            image {
              thumb: url(size: "original")
              focal
            }

            logo {
              thumb: url(size: "original")
              focal
            }

            links {
              id
              name
              url
            }

            metas {
              id
              key
              value
            }

            configs {
              id
              key
              value
            }

            url
          }
        }
      `
    }
  }
}

</script>
