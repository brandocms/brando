<template>
  <article v-if="fragment">
    <ContentHeader>
      <template #title>
        {{ $t('section.edit') }}
      </template>
    </ContentHeader>
    <PageSectionForm
      :page="fragment"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import PageSectionForm from './PageSectionForm'

export default {
  components: {
    PageSectionForm
  },

  inject: [
    'adminChannel'
  ],

  props: {
    sectionId: {
      type: [Number],
      required: true
    }
  },

  data () {
    return {
      loading: 0
    }
  },

  methods: {
    async save () {
      const fragmentParams = this.$utils.stripParams(this.fragment, ['__typename', 'id', 'creator', 'deletedAt', 'insertedAt'])
      this.$utils.serializeParams(fragmentParams, ['data'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateFragment($fragmentId: ID!, $fragmentParams: FragmentParams) {
              updateFragment(
                fragmentId: $fragmentId,
                fragmentParams: $fragmentParams,
              ) {
                id
              }
            }
          `,

          variables: {
            fragmentParams,
            fragmentId: this.sectionId
          }
        })

        this.$toast.success({ message: this.$t('section.updated') })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    fragment: {
      query: gql`
        query Fragment ($matches: FragmentMatches!) {
          fragment (matches: $matches) {
            id
            title
            parentKey
            pageId
            key
            language
            wrapper
            data
            creator {
              id
              name
            }
            insertedAt
            deletedAt
          }
        }
      `,
      variables () {
        return {
          matches: { id: this.sectionId }
        }
      },

      skip () {
        return !this.sectionId
      }
    }
  }
}
</script>
<i18n>
{
  "no": {
    "section.edit": "Endre innholdsseksjon",
    "section.updated": "Seksjon oppdatert"
  },
  "en": {
    "section.edit": "Edit section",
    "section.updated": "Section updated"
  }
}
</i18n>
