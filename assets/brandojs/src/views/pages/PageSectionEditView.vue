<template>
  <article v-if="pageFragment">
    <ContentHeader>
      <template v-slot:title>
        Endre innholdsseksjon
      </template>
    </ContentHeader>
    <PageSectionForm :page="pageFragment" :save="save" />
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

  inject: [
    'adminChannel'
  ],

  methods: {
    async save () {
      const pageFragmentParams = this.$utils.stripParams(this.pageFragment, ['__typename', 'id', 'creator', 'deleted_at', 'inserted_at'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdatePageFragment($pageFragmentId: ID!, $pageFragmentParams: PageFragmentParams) {
              updatePageFragment(
                pageFragmentId: $pageFragmentId,
                pageFragmentParams: $pageFragmentParams,
              ) {
                id
                title
                data
                key
                parent_key
                language
                updated_at
                page_id
              }
            }
          `,

          variables: {
            pageFragmentParams,
            pageFragmentId: this.sectionId
          },

          update: (store, { data: { updatePageFragment } }) => {
            const query = {
              query: GET_PAGES
            }
            const data = store.readQuery(query)
            const page = data.pages.find(page => parseInt(page.id) === parseInt(this.pageFragment.page_id))

            if (page) {
              const fragment = page.fragments.find(fragment => parseInt(fragment.id) === parseInt(this.sectionId))
              const idx = page.fragments.indexOf(fragment)

              page.fragments = [
                ...page.fragments.slice(0, idx),
                updatePageFragment,
                ...page.fragments.slice(idx + 1)
              ]

              // Write back to the cache
              store.writeQuery({
                ...query,
                data
              })
            } else {
              console.log('page not found?', data.pages, this.pageFragment.page_id)
            }
          }
        })

        this.$toast.success({ message: 'Seksjon opprettet' })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    pageFragment: {
      query: gql`
        query PageFragment ($pageFragmentId: ID!) {
          pageFragment (pageFragmentId: $pageFragmentId) {
            id
            title
            parent_key
            page_id
            key
            language
            wrapper
            data
            creator {
              id
              full_name
            }
            inserted_at
            deleted_at
          }
        }
      `,
      variables () {
        return {
          pageFragmentId: this.sectionId
        }
      },

      skip () {
        return !this.sectionId
      }
    }
  }
}
</script>
