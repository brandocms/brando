<template>
  <div class="imageseries">
    <ModalImageUpload
      :show-modal="selectedImageSeriesForUpload === imageSeries.id"
      :image-series="imageSeries"
      :upload-callback="uploadCallback"
      @close="closeUploadModal" />
    <div class="card-header-tab">
      <h2>Bildeserie: {{ imageSeries.name }}</h2>
      <ButtonSecondary
        @click.native.prevent="uploadToSeries(imageSeries)">
        Last opp bilder
      </ButtonSecondary>
      <ButtonSecondary
        :to="{ name: 'image-series-edit', params: { seriesId: imageSeries.id } }">
        Konfigurér
      </ButtonSecondary>
      <ButtonSecondary
        @click.native.prevent="deleteSeries(imageSeries)">
        Slett
      </ButtonSecondary>
    </div>
    <div class="card">
      <div
        v-if="images.length"
        class="card-body">
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
        v-if="modal"
        class="card-footer bg-white pt-0">
        <div class="w-50">
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
    </div>
  </div>
</template>

<script>

import BaseImage from './BaseImage.vue'
import ModalImageUpload from './modals/ModalImageUpload.vue'
import gql from 'graphql-tag'

export default {
  components: {
    BaseImage,
    ModalImageUpload
  },

  props: {
    imageSeries: {
      required: true,
      type: Object
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
      sortedArray: [],
      selectedImageSeriesForUpload: null
    }
  },

  computed: {
    images () {
      return this.imageSeries.images
    }
  },

  inject: [
    'adminChannel'
  ],

  methods: {
    getOrder (sortable) {
      return this.images
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray().map(Number)

      this.adminChannel.channel
        .push('images:sequence_images', { ids: this.sortedArray })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Rekkefølge oppdatert' })
        })
    },

    uploadToSeries (series) {
      this.selectedImageSeriesForUpload = series.id
    },

    closeUploadModal () {
      this.selectedImageSeriesForUpload = null
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
    margin-left: -0.25rem;
  }

  .imageseries {
    @space margin-bottom md;
  }
</style>
