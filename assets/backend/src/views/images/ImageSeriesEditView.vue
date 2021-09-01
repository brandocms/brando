<template>
  <article>
    <ContentHeader>
      <template #title>
        Endre bildeserie
      </template>
    </ContentHeader>
    <ImageSeriesForm
      :image-series="imageSeries"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import ImageSeriesForm from './ImageSeriesForm'
import GET_IMAGE_SERIES from '../../gql/images/IMAGE_SERIES_QUERY.graphql'

export default {
  components: {
    ImageSeriesForm
  },

  props: {
    imageSeriesId: {
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
      const imageSeriesParams = this.$utils.stripParams(this.imageSeries, [
        '__typename',
        'id',
        'creator',
        'images',
        'deletedAt',
        'insertedAt'])

      delete imageSeriesParams.cfg.__typename
      imageSeriesParams.cfg = JSON.stringify(imageSeriesParams.cfg)

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateImageSeries($imageSeriesId: ID!, $imageSeriesParams: ImageSeriesParams) {
              updateImageSeries(
                imageSeriesId: $imageSeriesId,
                imageSeriesParams: $imageSeriesParams
              ) {
                  id
                  name
                  slug

                  cfg {
                    uploadPath
                  }

                  creator {
                    id
                    name
                  }
                }
              }
          `,
          variables: {
            imageSeriesParams,
            imageSeriesId: this.imageSeries.id
          }
        })

        this.$toast.success({ message: 'Serie oppdatert' })
        this.$router.push({ name: 'images' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    imageSeries: {
      query: GET_IMAGE_SERIES,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          seriesId: this.imageSeriesId
        }
      },

      skip () {
        return !this.imageSeriesId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
