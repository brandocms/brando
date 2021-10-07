<template>
  <div class="imageseries">
    <ModalImageUpload
      :show-modal="selectedImageSeriesForUpload === imageSeries.id"
      :image-series="imageSeries"
      @save="addImageToSeries"
      @close="closeUploadModal" />
    <h2
      v-if="showHeader">
      Bildeserie &laquo;<strong>{{ imageSeries.name }}</strong>&raquo;
    </h2>
    <div class="button-group">
      <ButtonSecondary
        :narrow="true"
        @click.native.prevent="displayList = !displayList">
        <FontAwesomeIcon
          :icon="displayList ? 'image' : 'list'" />
      </ButtonSecondary>
      <ButtonSecondary
        v-if="showUpload"
        @click.native.prevent="uploadToSeries(imageSeries)">
        Last opp bilder
      </ButtonSecondary>
      <ButtonSecondary
        v-if="showConfig"
        :to="{ name: 'image-series-edit', params: { imageSeriesId: imageSeries.id } }">
        Konfigurér
      </ButtonSecondary>
      <ButtonSecondary
        v-if="showConfig && $can('recreate', imageSeries)"
        @click="reRender(imageSeries.id)">
        Gjenskap størrelser
      </ButtonSecondary>
      <ButtonSecondary
        v-if="showDelete"
        @click.native.prevent="deleteSeries(imageSeries)">
        Slett serie
      </ButtonSecondary>
    </div>

    <div
      v-if="images.length">
      <transition-group
        v-sortable="{handle: '.sort-handle', animation: 0, store: {get: getOrder, set: storeOrder}}"
        name="fade-move"
        tag="div"
        class="sort-container">
        <template v-for="i in images">
          <BaseImage
            :key="i.id"
            :data-id="i.id"
            class="sort-handle"
            :image="i"
            :display-list="displayList"
            :selected-images="selectedImages" />
        </template>
      </transition-group>
    </div>
    <div
      v-else
      class="empty-series">
      Ingen bilder i bildeserien
    </div>

    <div
      v-if="modal">
      <button
        class="btn btn-outline-secondary text-left"
        @click.prevent="uploadToSeries(imageSeries)">
        <i class="fal fa-fw mr-3 subtle fa-cloud" />
        Last opp bilder
      </button>
      <button
        class="btn btn-outline-secondary text-left"
        @click.prevent="deleteSeries(imageSeries)">
        <i class="fal fa-fw mr-3 subtle fa-trash" />
        Slett bildeserie
      </button>
      <button
        class="btn btn-outline-secondary text-left"
        @click.prevent="$emit('close')">
        <i class="fal fa-fw mr-3 subtle fa-window-close" />
        Lukk vindu
      </button>
    </div>
  </div>
</template>

<script>

import BaseImage from './BaseImage.vue'
import ModalImageUpload from './modals/ModalImageUpload.vue'
import gql from 'graphql-tag'
import GET_IMAGE_CATEGORY from '../../gql/images/IMAGE_CATEGORY_QUERY.graphql'

export default {
  components: {
    BaseImage,
    ModalImageUpload
  },

  inject: [
    'adminChannel'
  ],

  props: {
    imageSeries: {
      required: true,
      type: Object
    },

    // is the series inside a form?
    // we handle the upload differently
    inForm: {
      type: Boolean,
      default: false
    },

    showHeader: {
      type: Boolean,
      default: true
    },

    showUpload: {
      type: Boolean,
      default: true
    },

    showConfig: {
      type: Boolean,
      default: true
    },

    showDelete: {
      type: Boolean,
      default: true
    },

    selectedImages: {
      required: true,
      type: Array
    },

    uploadCallback: {
      type: Function,
      default: null
    },

    deleteCallback: {
      type: Function,
      default: null
    },

    /**
     * If true, will show buttons at bottom of series
     */
    modal: {
      type: Boolean,
      default: false
    }
  },

  data () {
    return {
      me: 'tets',
      displayList: false,
      sortedArray: [],
      selectedImageSeriesForUpload: null
    }
  },

  computed: {
    images () {
      return this.imageSeries.images
    }
  },

  methods: {
    getOrder (sortable) {
      return this.images
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray().map(Number)

      this.adminChannel.channel
        .push('images:sequence_images', { ids: this.sortedArray })
        .receive('ok', payload => {
          this.$emit('sort', this.sortedArray)
          this.$toast.success({ message: 'Rekkefølge oppdatert' })
        })
    },

    reRender (seriesId) {
      this.adminChannel.channel
        .push('images:rerender_image_series', { series_id: seriesId })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Bildeserie gjenskapt' })
        })
    },

    uploadToSeries (series) {
      this.selectedImageSeriesForUpload = series.id
    },

    closeUploadModal () {
      this.selectedImageSeriesForUpload = null
    },

    addImageToSeries (image) {
      this.imageSeries.images.push(image)
    },

    deleteSeries (series) {
      this.$alerts.alertConfirm('OBS', 'Er du sikker på at du vil slette denne bildeserien?', async (data) => {
        if (!data) {
          return
        }
        try {
          await this.$apollo.mutate({
            mutation: gql`
              mutation DeleteImageSeries($imageSeriesId: ID!) {
                deleteImageSeries(
                  imageSeriesId: $imageSeriesId,
                ) {
                  id
                }
              }
            `,

            variables: {
              imageSeriesId: series.id
            }
          })

          this.$emit('delete', series)
        } catch (err) {
          this.$utils.showError(err)
        }
      })
    }
  }
}
</script>

<style lang="postcss" scoped>
  .button-group {
    display: flex;
  }

  .empty-series {
    @space margin-top xs;
    background-color: theme(colors.peach);
    min-height: 120px;
    display: flex;
    justify-content: center;
    align-items: center;
  }

  .sort-container {
    @space margin-top xs;
    display: flex;
    flex-wrap: wrap;
    margin-left: -0.25rem;
  }

  .imageseries {
    @space margin-bottom md;
  }
</style>
