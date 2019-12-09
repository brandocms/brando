<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        Ny innholdsseksjon
      </template>
    </ContentHeader>
    <PageSectionForm :page="page" :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import GET_PAGES from '../../gql/pages/PAGES_QUERY.graphql'
import PageSectionForm from './PageSectionForm'

export default {
  components: {
    PageSectionForm
  },

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
        page_id: null,
        key: '',
        data: '',
        language: 'no',
        wrapper: ''
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    this.page.page_id = this.pageId
  },

  methods: {
    async save () {
      const pageFragmentParams = this.$utils.stripParams(this.page, ['__typename', 'id'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreatePageFragment($pageFragmentParams: PageFragmentParams) {
              createPageFragment(
                pageFragmentParams: $pageFragmentParams,
              ) {
                id
                title
                key
                data
                parent_key
                language
                updated_at
                page_id
              }
            }
          `,
          variables: {
            pageFragmentParams
          },
          update: (store, { data: { createPageFragment } }) => {
            const query = {
              query: GET_PAGES
            }
            const data = store.readQuery(query)
            const page = data.pages.find(page => parseInt(page.id) === parseInt(this.pageId))
            if (page) {
              page.fragments.push(createPageFragment)
              // Write back to the cache
              store.writeQuery({
                ...query,
                data
              })
            } else {
              console.log('page not found?', data.pages, this.pageId)
            }
          }
        })

        this.$toast.success({ message: 'Seksjon opprettet' })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>
