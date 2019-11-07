<template>
  <transition
    name="fade"
    appear>
    <div
      v-if="selectedImages.length"
      class="image-selection">
      <div class="container">
        <div class="float-right">
          <button
            class="btn btn-outline-secondary"
            @click.prevent="clearSelection">
            Avbryt
          </button>
          <button
            class="btn btn-secondary"
            @click.prevent="deleteImages">
            Slett <strong>{{ selectedImages.length }}</strong><template v-if="selectedImages.length === 1">
              valgt bilde
            </template><template v-else>
              valgte bilder
            </template>
          </button>
        </div>
      </div>
    </div>
  </transition>
</template>

<script>
import { mapActions } from 'vuex'

export default {
  components: {},

  props: {
    selectedImages: {
      type: Array,
      required: true,
      default: () => []
    },

    deleteCallback: {
      type: Function,
      default: null
    }
  },

  inject: [
    'adminChannel'
  ],

  data () {
    return {
      showModal: false
    }
  },

  methods: {
    clearSelection () {
      while (this.selectedImages.length) {
        this.selectedImages[0].click()
      }
    },

    deleteImages () {
      this.adminChannel.channel
        .push('images:delete_images', { ids: this.selectedImages.map(i => i.image.id) })
        .receive('ok', payload => {
          for (let i of this.selectedImages) {
            const { id, image_series_id: imageSeriesId } = i.image
            if (this.deleteCallback) {
              this.deleteCallback({ id, imageSeriesId })
            } else {
              this.deleteImage({ id, imageSeriesId })
            }
          }
          this.clearSelection()
          this.showConfirm = false
        })
    },

    ...mapActions('images', [
      'deleteImage'
    ])
  }
}
</script>
