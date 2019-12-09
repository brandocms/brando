<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        Ny innholdsside
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

  data () {
    return {
      page: {
        parent_id: null,
        key: '',
        title: '',
        slug: '',
        data: null,

        status: 'published',
        language: 'no',
        meta_description: ''
      }
    }
  },

  methods: {
    async save () {
      const pageParams = this.$utils.stripParams(this.page, ['__typename', 'id', 'slug', 'deleted_at'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreatePage($pageParams: PageParams) {
              createPage(
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
                  title
                  slug
                  data
                }
                children {
                  id
                  key
                  language
                  title
                  slug
                  data
                }
                fragments {
                  id
                  title
                  key
                  parent_key
                  language
                  updated_at
                  page_id
                  data
                }
                inserted_at
                updated_at
                deleted_at
              }
            }
          `,
          variables: {
            pageParams
          }
        })

        this.$toast.success({ message: 'Side opprettet' })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        console.log('calling showerror')
        this.$utils.showError(err)
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
