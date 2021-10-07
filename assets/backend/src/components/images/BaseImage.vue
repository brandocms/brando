<template>
  <div
    :class="{selected: selected, displayList: displayList, displayThumb: !displayList}"
    class="image-wrapper"
    @mouseover="mouseOver"
    @mouseout="mouseOut">
    <div
      v-show="!displayList && showOverlay"
      class="overlay"
      @click.stop.prevent="editImage">
      <i class="fa fa-search fa-fw" />
    </div>
    <KModal
      v-if="showEdit"
      ref="modal"
      ok-text="Lagre"
      @ok="saveEdit"
      @cancel="closeEdit">
      <template #header>
        Bildedetaljer
      </template>
      <div class="panes">
        <div>
          <KInput
            v-model="img.image.title"
            :value="img.image.title"
            name="img.image[title]"
            label="Bildetekst"
            placeholder="Bildetekst" />
          <KInput
            v-model="img.image.credits"
            :value="img.image.credits"
            name="img.image[credits]"
            label="Evt. kreditering"
            placeholder="Evt. kreditering" />
          <KInput
            v-model="img.image.alt"
            :value="img.image.alt"
            name="img.image[alt]"
            label="Alt tekst"
            placeholder="Beskrivelse av hva som er på bildet" />

          <div class="info">
            <dt>
              Filnavn
            </dt>
            <dd>
              {{ img.image.path }}
            </dd>
          </div>
        </div>
        <div class="shaded">
          <FocusPoint v-model="img.image.focal">
            <img
              :src="`${GLOBALS.identity.config.mediaUrl}/${img.image.path}?${timestamp}`"
              class="img-fluid">
          </FocusPoint>

          <div class="row info">
            <div class="col-md-6">
              <dt>
                Dimensjoner
              </dt>
              <dd v-if="img.image.width && img.image.height">
                {{ img.image.width }}x{{ img.image.height }}
              </dd>
              <dd v-else>
                Ingen dimensjoner
              </dd>
            </div>
          </div>

          <div class="row info">
            <div class="col-md-6">
              <ButtonSecondary
                @click="reRender(img.id)">
                Gjenskap størrelser
              </ButtonSecondary>
            </div>
          </div>
        </div>
      </div>
    </KModal>

    <template v-if="displayList">
      <div
        class="list-row"
        @click.stop.prevent="click">
        <div class="thumbnail">
          <img
            :src="img.image.sizes.thumb + '?' + timestamp"
            class="img-fluid" />
        </div>
        <div class="filename">
          {{ img.image.path }}
        </div>
        <div class="dims">
          {{ img.image.width }}x{{ img.image.height }}
        </div>
        <div class="edit">
          <button
            @click.stop.prevent="editImage">
            Editer
          </button>
        </div>
      </div>
    </template>
    <template v-else>
      <img
        :src="img.image.sizes.thumb + '?' + timestamp"
        class="img-fluid"
        @click.stop.prevent="click">
    </template>
  </div>
</template>

<script>

import gql from 'graphql-tag'
import { format, parseISO } from 'date-fns'
import FocusPoint from './FocusPoint.vue'

export default {
  components: {
    FocusPoint
  },

  inject: [
    'adminChannel',
    'GLOBALS'
  ],

  props: {
    image: {
      required: true,
      type: Object
    },

    selectedImages: {
      type: Array,
      required: true,
      default: () => []
    },

    displayList: {
      type: Boolean,
      default: false
    }
  },

  data () {
    return {
      cacheBuster: '',
      img: {},
      selected: false,
      showEdit: false,
      showOverlay: false
    }
  },

  computed: {
    timestamp () {
      return format(parseISO(this.img.updatedAt), 'T') + this.cacheBuster
    }
  },

  created () {
    this.img = this.$utils.clone(this.image)
  },

  methods: {
    reRender (imgId) {
      this.adminChannel.channel
        .push('images:rerender_image', { id: imgId })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Størrelser gjenskapt' })
          this.cacheBuster = this.$utils.guid()
        })
    },

    mouseOver () {
      this.showOverlay = true
    },

    mouseOut () {
      this.showOverlay = false
    },

    editImage () {
      this.showEdit = true
      this.showOverlay = false
    },

    closeEdit () {
      this.$refs.modal.close().then(() => {
        this.$nextTick(() => {
          this.showEdit = false
          this.selected = false
          this.showOverlay = false
        })
      })
    },

    async saveEdit () {
      const imageMetaParams = {
        alt: this.img.image.alt,
        credits: this.img.image.credits,
        title: this.img.image.title,
        focal: this.img.image.focal
      }
      const imageParams = this.$utils.stripParams(this.img, ['__typename', 'id', 'deletedAt'])
      this.$utils.validateImageParams(imageParams, ['image'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateImageMeta($imageId: ID!, $imageMetaParams: ImageMetaParams) {
              updateImageMeta(
                imageId: $imageId,
                imageMetaParams: $imageMetaParams
              ) {
                id
                image {
                  path
                  credits
                  title
                  alt
                  focal
                  width
                  height
                  sizes
                  thumb: url(size: "thumb")
                  medium: url(size: "medium")
                }
                imageSeriesId
                sequence
                updatedAt
                deletedAt
              }
            }
          `,
          variables: {
            imageMetaParams,
            imageId: this.img.id
          }
        })

        this.$toast.success({ message: 'Bilde oppdatert' })
        this.$router.push({ name: 'images' })
      } catch (err) {
        this.$utils.showError(err)
      }

      this.showEdit = false
      this.selected = false
      this.showOverlay = false
    },

    click (ev) {
      // don't select if modal is open.
      if (!this.showEdit) {
        this.selected = !this.selected
        if (this.selected) {
          this.selectedImages.push(this)
        } else {
          const idx = this.selectedImages.indexOf(this)
          this.selectedImages.splice(idx, 1)
        }
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
.image-wrapper {

  &.displayThumb {
    border: 5px solid #000;
    cursor: pointer;
    height: 125px;
    padding: 2px;
    position: relative;
    width: 125px;
    margin: 0.25rem;

    &.selected {
      background-color: theme(colors.blue);
      border: 5px solid theme(colors.blue);
      padding: 0;

      img {
        opacity: 0.50;
      }
    }
  }

  &.displayList {
    width: 100%;
    margin: 0.25rem 0;
    background-color: theme(colors.peach);
    display: flex;
    line-height: 1;

    &.selected {
      background-color: theme(colors.blue);
      color: theme(colors.peach);
      padding: 0;

      img {
        opacity: 0.50;
      }

      .list-row {
        > .edit {
          button {
            border: 1px solid theme(colors.peach);
          }
        }
      }
    }

    .list-row {
      display: flex;
      align-items: center;
      width: 100%;
      padding: 12px 12px;

      > .thumbnail {
        width: 50px;
        margin-right: 25px;
      }

      > .filename {
        width: inherit;
        margin-top: 4px;
      }

      > .dims {
        margin-top: 4px;
      }

      > .edit {
        button {
          margin-left: 15px;
          border: 1px solid theme(colors.blue);
          padding: 8px 15px 8px;
        }
      }
    }
  }

  &.sort-handle {
    cursor: move;
  }

  .overlay {
    align-items: center;
    background-color: theme(colors.blue);
    color: theme(colors.peach);
    border-radius: 15px;
    display: flex;
    height: 30px;
    justify-content: center;
    opacity: 0.5;
    position: absolute;
    right: 5px;
    top: 5px;
    transition: all 500ms ease;
    width: 30px;

    &:hover {
      opacity: 1;
      transition: all 250ms ease;
    }

    svg {
      padding: 4px;
      color: theme(colors.peach);
      text-align: center;
      transition: all 500ms ease;
    }
  }

  img {
    opacity: 1;
  }
}

.img-border-lg {
  border: 5px solid #000;
}

dt {
  @fontsize sm;
  font-weight: 500;
}

dd {
  @fontsize sm;
}

.info {
  @space margin-y xs;
}

.btn-outline-secondary {
  @fontsize base;
  height: 60px;

  + .btn-outline-secondary {
    margin-top: -1px;
  }
}

</style>
