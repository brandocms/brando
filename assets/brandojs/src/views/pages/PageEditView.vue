<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        Endre innholdsside
      </template>
    </ContentHeader>
    <PageForm :page="page" :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import PageForm from './PageForm'

export default {
  components: {
    PageForm
  },

  props: {
    pageId: {
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
      const pageParams = this.$utils.stripParams(this.page, ['__typename', 'id', 'slug', 'deleted_at', 'inserted_at'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdatePage($pageId: ID!, $pageParams: PageParams) {
              updatePage(
                pageId: $pageId,
                pageParams: $pageParams
              ) {
                id
                key
                title
                slug
                language
                data

                parent {
                  id
                  key
                  language
                  data
                  title
                  slug
                }

                children {
                  id
                  key
                  language
                  title
                  data
                  slug
                }
                fragments {
                  id
                  title
                  key
                  parent_key
                  data
                  language
                  updated_at
                  page_id
                }
                inserted_at
                updated_at
                deleted_at
              }
            }
          `,
          variables: {
            pageParams,
            pageId: this.page.id
          }
        })

        this.$toast.success({ message: 'Side oppdatert' })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    page: {
      query: gql`
        query Page ($pageId: ID!) {
          page (pageId: $pageId) {
            id
            key
            language
            title
            slug
            data
            status
            css_classes
            parent_id
            meta_description
            inserted_at
            deleted_at
          }
        }
      `,
      variables () {
        return {
          pageId: this.pageId
        }
      },

      skip () {
        return !this.pageId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
