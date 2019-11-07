<template>
  <div class="card-wrapper mb-4">
    <ModalImageUpload
      :show-modal="selectedImageSeriesForUpload === imageSeries.id"
      :image-series="imageSeries"
      :upload-callback="uploadCallback"
      @close="closeUploadModal" />
    <div class="card-header-tab">
      <b-dropdown
        variant="white"
        no-caret>
        <template slot="button-content">
          <i class="k-dropdown-icon" />
        </template>
        <button
          class="dropdown-item"
          @click.prevent="uploadToSeries(imageSeries)">
          <i class="fal fa-fw mr-3 subtle fa-cloud" />
          Last opp bilder til denne bildeserien
        </button>
        <router-link
          :to="{ name: 'image-series-config', params: { seriesId: imageSeries.id } }"
          tag="button"
          class="dropdown-item">
          <i class="fal fa-fw mr-3 subtle fa-cog" />
          Konfigurér bildeserie
        </router-link>
        <button
          class="dropdown-item"
          @click.prevent="deleteSeries(imageSeries)">
          <i class="fal fa-fw mr-3 subtle fa-trash" />
          Slett bildeserie
        </button>
      </b-dropdown>
      <h5>{{ imageSeries.name }}</h5>
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
        class="card-body text-center">
        <svg
          height="300px"
          width="300px"
          fill="#000000"
          xmlns="http://www.w3.org/2000/svg"
          xmlns:xlink="http://www.w3.org/1999/xlink"
          version="1.1"
          x="0px"
          y="0px"
          viewBox="0 0 64 64"
          enable-background="new 0 0 64 64"
          xml:space="preserve"><g><g><path d="M4.17,16.89v41.37h44.51V16.89H4.17z M46.68,56.26H6.17V42.24l16.9-6.54l10.989,5.23L41.13,38l5.55,3.6V56.26z     M46.68,39.22l-5.35-3.47l-7.21,2.99l-10.96-5.21L6.17,40.09v-21.2h40.51V39.22z"></path></g><g><path d="M13.54,23.17c-1.97,0-3.58,1.6-3.58,3.57c0,1.97,1.61,3.57,3.58,3.57c1.96,0,3.57-1.6,3.57-3.57    C17.11,24.77,15.5,23.17,13.54,23.17z M13.54,28.31c-0.87,0-1.58-0.7-1.58-1.57c0-0.86,0.71-1.57,1.58-1.57    c0.86,0,1.57,0.71,1.57,1.57C15.11,27.61,14.4,28.31,13.54,28.31z"></path></g><g><polygon points="54.25,11.32 54.25,50.29 52.25,50.29 52.25,13.32 10.75,13.32 10.75,11.32   "></polygon></g><g><polygon points="59.83,5.74 59.83,44.72 57.83,44.72 57.83,7.74 16.32,7.74 16.32,5.74   "></polygon></g></g></svg><br>
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

import { mapActions } from 'vuex'
import BaseImage from './BaseImage.vue'
import ModalImageUpload from './modals/ModalImageUpload.vue'
import { alertConfirm } from '../../utils/alerts'
import { imageAPI } from '../../api/image'

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
      this.sortedArray = sortable.toArray()

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
      alertConfirm('OBS', 'Er du sikker på at du vil slette denne bildeserien?', async (data) => {
        if (!data) {
          return
        }
        if (this.deleteCallback) {
          await imageAPI.deleteImageSeries(series.id)
          this.deleteCallback(series)
        } else {
          this.deleteImageSeries(series)
        }
      })
    },

    ...mapActions('images', [
      'deleteImageSeries'
    ])
  }
}
</script>
