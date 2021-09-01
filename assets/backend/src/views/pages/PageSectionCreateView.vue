<template>
  <article>
    <ContentHeader>
      <template #title>
        {{ $t('section.new') }}
      </template>
    </ContentHeader>
    <PageSectionForm
      :page="page"
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
    'adminChannel',
    'GLOBALS'
  ],

  props: {
    pageId: {
      type: [String, Number],
      required: true
    }
  },

  data () {
    return {
      loading: 0,
      page: {
        pageId: null,
        language: null,
      }
    }
  },

  created () {
    this.page.pageId = this.pageId
    this.page.language = this.GLOBALS.identity.defaultLanguage
  },

  methods: {
    async save () {
      const fragmentParams = this.$utils.stripParams(this.page, ['__typename', 'id'])
      this.$utils.serializeParams(fragmentParams, ['data'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateFragment($fragmentParams: FragmentParams) {
              createFragment(
                fragmentParams: $fragmentParams,
              ) {
                id
              }
            }
          `,
          variables: {
            fragmentParams
          }
        })

        this.$toast.success({ message: this.$t('section.created') })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>
<i18n>
{
  "no": {
    "section.new": "Ny innholdsseksjon",
    "section.created": "Seksjon opprettet"
  },
  "en": {
    "section.new": "New section",
    "section.created": "Section created"
  }
}
</i18n>
