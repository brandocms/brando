<template>
  <div>
    <Block
      ref="block"
      :block="block"
      :parent="parent"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <div
        ref="block"
        class="villain-block-gallery">
        <transition-group
          v-if="block.data.images.length"
          v-sortable="{handle: '.villain-block-gallery-image', animation: 500, store: {get: getOrder, set: storeOrder}}"
          name="fade-move"
          tag="div"
          class="villain-block-gallery-images">
          <div
            v-for="i in block.data.images"
            :key="i.url"
            :data-id="i.url"
            class="villain-block-gallery-image"
            @mouseover.stop="imgHover(i, $event)"
            @mouseout="imgLeave"
            @click="toggleImage(i)">
            <i class="fa fa-trash info" />
            <div
              v-if="toggledImageUrl === i.url"
              class="villain-block-gallery-image-overlay">
              <FontAwesomeIcon
                icon="trash"
                size="4x"
                @click="del(i)" />
            </div>
            <img
              :src="i.url"
              class="img-fluid">
          </div>
        </transition-group>
        <div
          v-else
          class="villain-block-image-empty">
          <FontAwesomeIcon
            icon="images"
            size="6x" />
        </div>
        <div
          key="actions"
          class="actions">
          <ButtonTiny
            @click="$refs.config.openConfig()">
            {{ $t('configure') }}
          </ButtonTiny>
        </div>
      </div>

      <template slot="help">
        <p v-html="$t('help')" />
      </template>
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <div class="buttons mb-3">
          <template
            v-if="block.data.images.length">
            <ButtonSecondary
              v-if="listStyle"
              @click="listStyle = false; showUpload = false; showTitles = false; showImages = true">
              {{ $t('grid') }}
            </ButtonSecondary>
            <ButtonSecondary
              v-else
              @click="listStyle = true; showUpload = false; showTitles = false; showImages = true">
              {{ $t('list') }}
            </ButtonSecondary>
            <ButtonSecondary @click="showUpload = true; showImages = false; showTitles = false">
              {{ $t('upload-images') }}
            </ButtonSecondary>
            <ButtonSecondary @click="showTitles = true; showImages = false; showUpload = false">
              {{ $t('edit-captions') }}
            </ButtonSecondary>
          </template>
        </div>
        <div
          v-if="showTitles"
          class="title-cfg">
          <KInputTable
            v-model="block.data.images"
            name="data[images]"
            :label="$t('captions')"
            id-key="url"
            :sortable="false"
            :delete-rows="false"
            :add-rows="false">
            <template #row="{ entry }">
              <div class="panes">
                <div>
                  <td>
                    <img :src="entry.sizes.thumb">
                  </td>
                </div>
                <div>
                  <td>
                    <KInput
                      v-model="entry.title"
                      name="entry[title]"
                      :placeholder="$t('caption')"
                      :label="$t('caption')" />

                    <KInput
                      v-model="entry.alt"
                      name="entry[alt]"
                      :placeholder="$t('alt-text')"
                      :label="$t('alt-text')"
                      :help-text="$t('alt-text-help')" />
                  </td>
                </div>
              </div>
            </template>
            <template #new="">
            </template>
          </KInputTable>
        </div>
        <div
          v-if="showUpload">
          <div
            class="display-icon">
            <drop
              class="drop"
              @dragover="dragOver = true"
              @dragleave="dragOver = false"
              @drop="handleDrop">
              <template v-if="dragOver">
                <i class="fa fa-fw fa-cloud-upload-alt"></i>
              </template>
              <template
                v-else>
                <template v-if="uploading">
                  <i class="fa fa-fw fa-circle-notch fa-spin"></i>
                </template>
                <template v-else>
                  <i class="fa fa-fw fa-images"></i>
                </template>
              </template>
            </drop>
          </div>
          <div class="text-center mb-3">
            <template
              v-if="dragOver">
              {{ $t('drop-to-upload') }}
            </template>
            <template v-else>
              <template v-if="uploading">
                {{ $t('uploading') }} ...
              </template>
              <template v-else>
                {{ $t('drag-images-to-upload') }} &uarr;
              </template>
            </template>
          </div>
        </div>
        <div
          v-if="showImages && listStyle"
          class="villain-image-library mt-4">
          <table
            class="table villain-image-table">
            <tr
              v-for="i in images"
              :key="i.id">
              <td class="fit">
                <img
                  :src="i.thumb"
                  :class="alreadySelected(i) ? 'villain-image-table-selected' : ''"
                  class="img-fluid"
                  @click="selectImage(i)" />
              </td>
              <td>
                <table class="table table-bordered">
                  <tr>
                    <td>
                      <span class="text-mono">{{ i.src.substring(i.src.lastIndexOf('/')+1) }}</span>
                    </td>
                    <td>
                      <span class="text-mono text-align-right">
                        {{ i.width }}x{{ i.height }}
                      </span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </div>

        <div
          v-else-if="showImages && !listStyle"
          class="villain-image-library row">
          <div
            v-for="i in images"
            :key="i.id"
            class="imgthumb mb-3">
            <img
              :src="i.thumb"
              :class="alreadySelected(i) ? 'villain-image-table-selected' : ''"
              class="img-fluid"
              @click="selectImage(i)" />
          </div>
          <div
            class="col-12 form-group mt-4">
            <KInput
              v-model="block.data.class"
              name="block[data][class]"
              label="CSS klasser" />
          </div>
          <div
            class="col-12 form-group mt-4">
            <KInputRadios
              v-model="block.data.placeholder"
              :options="[
                {label: 'SVG', value: 'svg'},
                {label: 'Dominant color', value: 'dominant_color'},
                {label: 'Micro', value: 'micro'},
              ]"
              option-value-key="value"
              option-label-key="label"
              name="block[data][placeholder]"
              label="Placeholder type" />
          </div>
        </div>

        <div class="villain-config-content-buttons">
          <button
            v-if="!showImages && !showTitles"
            type="button"
            class="btn btn-primary"
            @click="showImages = true; showUpload = false; showTitles = false">
            {{ $t('pick-from-library') }}
          </button>
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'
import { Drop } from 'vue-drag-drop'

export default {
  name: 'GalleryBlock',

  components: {
    Block,
    Drop
  },

  inject: [
    'urls',
    'headers',
    'available',
    'refresh'
  ],

  props: {
    block: {
      type: Object,
      default: () => {}
    },

    parent: {
      type: String,
      default: null
    }
  },

  data () {
    return {
      uid: null,
      codeMirror: null,
      showConfig: false,
      showImages: true,
      showUpload: false,
      showTitles: false,
      dragOver: false,
      uploading: false,
      images: [],
      listStyle: false,
      toggledImageUrl: null,
      editImage: null
    }
  },

  computed: {
    seriesSlug () {
      return this.block.data.series_slug ? this.block.data.series_slug : 'post'
    },

    browseURL () {
      return this.urls.browse + this.seriesSlug
    },

    uploadURL () {
      return `${this.urls.base}upload`
    }
  },

  created () {
    this.getImages()

    if (!this.block.data.images.length) {
      this.showImages = false
      this.showUpload = true
    }
  },

  methods: {
    toggleImage (img) {
      if (this.toggledImageUrl === img.url) {
        this.toggledImageUrl = null
        return
      }
      this.toggledImageUrl = img.url
    },

    del (img) {
      const i = this.block.data.images.find(i => i.url === img.url)
      if (i) {
        const idx = this.block.data.images.indexOf(i)
        this.block.data.images = [
          ...this.block.data.images.slice(0, idx),
          ...this.block.data.images.slice(idx + 1)
        ]
      }
    },

    alreadySelected (img) {
      if (this.block.data.images.find(i => i.url === img.src)) {
        return true
      }
      return false
    },

    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    },

    getOrder (sortable) {
      return this.block.data.images
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray()
      let newImages = []
      this.sortedArray.forEach(x => {
        const i = this.block.data.images.find(i => i.url === x)
        newImages = [
          ...newImages,
          i
        ]
      })
      this.block.data.images = newImages
    },

    imgHover (i, e) {
      if (this.toggledImageUrl !== i.url) {
        e.currentTarget.classList.add('hover')
      }
    },

    imgLeave (e) {
      e.currentTarget.classList.remove('hover')
    },

    async getImages () {
      const headers = new Headers()
      headers.append('accept', 'application/json, text/javascript, */*; q=0.01')

      if (this.headers.extra) {
        for (const key of Object.keys(this.headers.extra)) {
          headers.append(key, this.headers.extra[key])
        }
      }

      const request = new Request(this.browseURL, { headers })

      try {
        const response = await fetch(request)
        const data = await response.json()

        if (data.images.length) {
          this.images = data.images
        } else {
          this.images = []
        }
      } catch (e) {
        this.$alerts.alertError('Feil', 'Klarte ikke koble til bildebiblioteket!')
        console.error(e)
      }
    },

    async handleDrop (data, event) {
      event.preventDefault()
      const files = event.dataTransfer.files

      if (files) {
        for (let i = 0; i < files.length; i++) {
          try {
            await this.upload(files.item(i))
          } catch (e) {
            this.$alerts.alertError(this.$t('error'), this.$t('error-uploading'))
            break
          }
        }
      }

      this.showImages = false
      this.uploading = false
      this.showTitles = true
      this.showUpload = false
      this.$refs.config.closeConfig()
    },

    async upload (f) {
      const headers = new Headers()
      headers.append('accept', 'application/json, text/javascript, */*; q=0.01')

      if (this.headers.extra) {
        for (const key of Object.keys(this.headers.extra)) {
          headers.append(key, this.headers.extra[key])
        }
      }

      const formData = new FormData()
      formData.append('image', f)
      formData.append('slug', this.seriesSlug)
      formData.append('name', f.name)
      formData.append('uid', this.createUID())

      const request = new Request(this.uploadURL, { headers, method: 'post', body: formData })

      try {
        this.dragOver = false
        this.uploading = true
        const response = await fetch(request)
        const data = await response.json()

        if (data.status === 200) {
          this.block.data.images = [
            ...this.block.data.images,
            {
              sizes: data.image.sizes,
              credits: '',
              title: '',
              url: data.image.src,
              width: data.image.width,
              height: data.image.height,
              dominant_color: data.image.dominant_color,
              webp: data.image.webp
            }
          ]
        } else {
          this.uploading = false
          this.$alerts.alertError(this.$t('error'), this.$t('error-uploading-info', { error: data.error }))
        }
      } catch (e) {
        this.uploading = false
        throw (e)
      }
    },

    selectImage (img) {
      if (this.alreadySelected(img)) {
        return
      }

      this.$set(this.block.data, 'images', [
        ...this.block.data.images,
        {
          sizes: img.sizes,
          credits: img.credits,
          title: img.title,
          url: img.src,
          dominant_color: img.dominant_color,
          width: img.width,
          height: img.height,
          webp: img.webp
        }
      ])
    }
  }
}
</script>
<style lang="postcss" scoped>
  .villain-block-gallery {
    width: 100%;
    position: relative;

    .villain-block-gallery-popup-wrapper {
      .villain-block-gallery-popup {
        padding: 2rem 3rem;
        min-width: 760px;
        margin-left: auto;
        margin-right: 0;
        display: -webkit-box;
        display: -ms-flexbox;
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        background-color: white;
        border: 1px solid #eee;
        position: fixed;
        z-index: 99999;
        left: 50%;
        transform: translateX(-50%);
      }
    }

    .villain-block-gallery-images-meta {
      margin: 0 auto;
      margin-top: 40px;
      margin-bottom: 10px;
      max-width: 275px;

      label {
        text-align: center;
        width: 100%;
      }

      input:focus {
        border: 1px solid #ced4da;
      }
    }

    .villain-block-gallery-images {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      width: 100%;
      justify-content: center;

      .villain-block-gallery-image {
        position: relative;
        padding: .5rem;
        user-select: none;
        width: 25%;
        cursor: pointer;

        .info {
          position: absolute;
          left: 50%;
          top: 50%;
          color: #fff;
          font-size: 3em;
          transform: translateX(-50%) translateY(-50%);
          transition: opacity 0.75s ease;
          opacity: 0;
        }

        &.hover {
          .info {
            opacity: 0.8;
          }
        }

        .villain-block-gallery-image-delete-overlay {
          user-select: none;
          display: flex;
          justify-content: center;
          align-items: center;
          color: rgba(0,0,0,0.3);
          position: absolute;
          opacity: 0;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          cursor: no-drop;
          display: none;
        }

        .villain-block-gallery-image-overlay {
          user-select: none;
          display: flex;
          justify-content: center;
          align-items: center;
          color: #fff;
          background-color: #000fe0cf;
          position: absolute;
          opacity: 1;
          top: 0;
          left: 0;
          z-index: 2;
          width: 100%;
          height: 100%;

          i {
            padding: 0 15px;
            cursor: pointer;
          }
        }
      }
    }
  }


  .imgthumb {
    width: 150px;
  }

  .villain-block-image-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;

    svg {
      height: auto;
      max-width: 250px;
    }
  }

  .image-caption {
    align-self: center;
  }

  .actions {
    text-align: center;
  }

  >>> .buttons {
    display: flex;
  }

  .title-cfg {
    >>> .panes {
      padding-top: 20px;
      & > * {
        min-width: auto !important;
      }
    }
  }
</style>

<i18n>
  {
    "en": {
      "configure": "Configure gallery block",
      "help": "To remove an image from the gallery, first click the image, then click the trashcan icon.<br><br>To caption images, click \"Configure gallery block\", then \"Edit captions\"<br><br>To sort, you can drag and drop the images in your prefered sequence",
      "grid": "Grid",
      "list": "List",
      "upload-images": "Upload images",
      "edit-captions": "Edit captions",
      "alt-text": "Alt. text",
      "alt-text-help": "Image description for accessibility",
      "caption": "Caption",
      "captions": "Captions",
      "drop-to-upload": "Drop to upload!",
      "uploading": "Uploading",
      "drag-images-to-upload": "Drag and drop your wanted images here",
      "pick-from-library": "Pick images from library",
      "error": "Error",
      "error-uploading": "Error uploading :(",
      "error-uploading-info": "Error uploading :(\n\n{error}"
    },
    "no": {
      "configure": "Konfigurér galleriblokk",
      "help": "For å slette et bilde i galleriet, klikker du på bildet, deretter klikker du på søplekasse-ikonet<br><br>For å gi bildene bildetekst, klikker du på \"Konfigurér galleriblokk\" og deretter \"Endre bildetekster\"<br><br>For å sortere bildene kan du dra og slippe de i ønsket rekkefølge.",
      "grid": "Grid",
      "list": "List",
      "upload-images": "Last opp bilder",
      "edit-captions": "Endre bildetekster",
      "alt-text": "Alt. tekst",
      "alt-text-help": "Beskrivelse av bildet for universell utforming",
      "caption": "Bildetekst",
      "captions": "Bildetekster",
      "drop-to-upload": "Slipp for å laste opp!",
      "uploading": "Laster opp",
      "drag-images-to-upload": "Dra og slipp bildene du vil laste opp hit",
      "pick-from-library": "Velg bilder fra bildebibliotek",
      "error": "Feil",
      "error-uploading": "Feil ved opplasting :(",
      "error-uploading-info": "Feil ved opplasting :(\n\n{error}"
    }
  }
</i18n>
