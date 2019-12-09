<template>
  <transition
    name="fade"
    appear>
    <div
      v-if="selectedImages.length"
      class="image-selection">
      <button
        class="btn btn-outline-secondary"
        @click.prevent="clearSelection">
        Avbryt
      </button>
      <button
        class="btn btn-outline-secondary"
        @click.prevent="deleteImages">
        Slett <div class="circle"><span>{{ selectedImages.length }}</span></div><template v-if="selectedImages.length === 1">
          valgt bilde
        </template><template v-else>
          valgte bilder
        </template>
      </button>
    </div>
  </transition>
</template>

<script>

export default {
  components: {},

  props: {
    selectedImages: {
      type: Array,
      required: true,
      default: () => []
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
            this.$emit('delete', { id, imageSeriesId })
          }
          this.clearSelection()
          this.showConfirm = false
        })
    }
  }
}
</script>

<style lang="postcss" scoped>
  .image-selection {
    background-color: theme(colors.dark);
    border-top: 5px solid white;
    bottom: 0;
    left: 0;
    padding: 1rem;
    position: fixed;
    width: 100%;
    z-index: 100000;
    color: theme(colors.peach);

    display: flex;
    justify-content: flex-end;
  }

  .btn-outline-secondary {
    border: 1px solid theme(colors.peach);
    color: theme(colors.peach);
    width: auto;
    padding-left: 25px;
    padding-right: 25px;
    height: 60px;
    display: inline-flex;
    align-items: center;

    + .btn-outline-secondary {
      margin-left: 15px;
    }

    .circle {
      display: inline-flex;
      margin-top: -5px;
      margin-left: 10px;
      margin-right: 10px;
      border-color: theme(colors.peach);

      span {
        color: theme(colors.peach);
      }
    }

    &:hover {
      color: theme(colors.dark);

      .circle {
        border-color: theme(colors.dark);
        span {
          color: theme(colors.dark);
        }
      }
    }
  }

  .img-border-lg {
    border: 5px solid #000;
  }
</style>
