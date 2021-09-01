<template>
  <article v-if="GLOBALS.identity">
    <ContentHeader>
      <template #title>
        {{ $t('pages.new') }}
      </template>
    </ContentHeader>
    <PageForm
      :page="page"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import PageForm from './PageForm'
import locale from '../../locales/pages'

export default {
  components: {
    PageForm
  },

  inject: ['GLOBALS'],

  props: {
    pageId: {
      type: Number,
      required: false,
      default: null
    }
  },

  data () {
    return {
      page: {
        parentId: null,
        uri: null,
        title: '',
        data: null,
        template: 'default.html',
        status: 'draft',
        language: null,
        metaDescription: '',
        properties: []
      }
    }
  },

  created () {
    this.page.parentId = this.pageId
    this.page.language = this.GLOBALS.identity.defaultLanguage
  },

  methods: {
    async save () {
      let pageParams = this.$utils.stripParams(this.page, ['__typename', 'id', 'slug', 'deletedAt'])

      const properties = pageParams.properties.map(g => {
        return { ...g, data: JSON.stringify(g.data) }
      })

      pageParams = { ...pageParams, properties: properties }

      this.$utils.validateImageParams(pageParams, ['metaImage'])
      this.$utils.serializeParams(pageParams, ['data'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreatePage($pageParams: PageParams) {
              createPage(
                pageParams: $pageParams
              ) {
                id
              }
            }
          `,
          variables: {
            pageParams
          }
        })

        this.$toast.success({ message: this.$t('pages.created') })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  i18n: {
    sharedMessages: locale
  }
}
</script>
