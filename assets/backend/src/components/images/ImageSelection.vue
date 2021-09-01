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
        Slett <div class="circle">
          <span>{{ selectedImages.length }}</span>
        </div><template v-if="selectedImages.length === 1">
          valgt bilde
        </template><template v-else>
          valgte bilder
        </template>
      </button>
    </div>
  </transition>
</template>

<script>

import gql from 'graphql-tag'

export default {
  components: {},

  inject: [
    'adminChannel'
  ],

  props: {
    selectedImages: {
      type: Array,
      required: true,
      default: () => []
    }
  },

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
      const imageIds = this.selectedImages.map(i => i.image.id)
      const imageIdsWithSeriesId = this.selectedImages.map(i => ({ id: i.image.id, imageSeriesId: i.image.imageSeriesId }))
      this.$apollo.mutate({
        mutation: gql`
          mutation DeleteImages($imageIds: [ID]) {
            deleteImages(
              imageIds: $imageIds
            )
          }
        `,
        variables: {
          imageIds: imageIds
        }
      }).then(res => {
        imageIdsWithSeriesId.forEach(i => this.$emit('delete', { id: i.id, imageSeriesId: i.imageSeriesId }))
        this.clearSelection()
      }).catch(e => {
        console.error(e)
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
      margin-top: 0;
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
