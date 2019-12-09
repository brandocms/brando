<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        Endre bildekategori
      </template>
    </ContentHeader>
    <ImageCategoryForm :imageCategory="imageCategory" :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import ImageCategoryForm from './ImageCategoryForm'
import GET_IMAGE_CATEGORY from '../../gql/images/IMAGE_CATEGORY_QUERY.graphql'

export default {
  components: {
    ImageCategoryForm
  },

  props: {
    imageCategoryId: {
      type: [Number],
      required: true
    }
  },

  data () {
    return {
    }
  },

  methods: {
    async save () {
      const imageCategoryParams = this.$utils.stripParams(this.imageCategory, [
        '__typename',
        'id',
        'creator',
        'image_series',
        'image_series_count',
        'deleted_at',
        'inserted_at'])

      delete imageCategoryParams.cfg.__typename
      imageCategoryParams.cfg = JSON.stringify(imageCategoryParams.cfg)

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdatePage($imageCategoryId: ID!, $imageCategoryParams: PageParams) {
              updateImageCategory(
                imageCategoryId: $imageCategoryId,
                imageCategoryParams: $imageCategoryParams
              ) {
                  id
                  name
                  slug

                  cfg {
                    upload_path
                  }

                  creator {
                    id
                    full_name
                  }
                }
              }
          `,
          variables: {
            imageCategoryParams,
            imageCategoryId: this.imageCategory.id
          }
        })

        this.$toast.success({ message: 'Kategori oppdatert' })
        this.$router.push({ name: 'images' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    imageCategory: {
      query: GET_IMAGE_CATEGORY,
      variables () {
        return {
          categoryId: this.imageCategoryId
        }
      },

      skip () {
        return !this.imageCategoryId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
