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
      <div class="villain-block-picture">
        <template v-if="previewUrl">
          <img
            v-if="previewUrl"
            :src="previewUrl"
            class="img-fluid">
          <div class="villain-block-picture-caption">
            <div v-if="block.data.title">
              <span>{{ $t('title') }}</span>{{ block.data.title }}
            </div>
            <div v-if="block.data.alt">
              <span>{{ $t('alt') }}</span>{{ block.data.alt }}
            </div>
            <div v-if="block.data.credits">
              <span>{{ $t('credits') }}</span>{{ block.data.credits }}
            </div>
          </div>
          <div class="helpful-actions">
            <ButtonTiny
              @click="$refs.config.openConfig()">
              {{ $t('configure') }}
            </ButtonTiny>
          </div>
        </template>
        <div
          v-else
          class="villain-block-image-empty">
          <drop
            class="drop"
            @dragover="dragOver = true"
            @dragleave="dragOver = false"
            @drop="handleDrop">
            <template v-if="dragOver">
              <FontAwesomeIcon
                icon="cloud-upload-alt"
                size="6x"
                fixed-width />
            </template>
            <template
              v-else>
              <template v-if="uploading">
                <FontAwesomeIcon
                  icon="circle-notch"
                  spin
                  size="6x"
                  fixed-width />
              </template>
              <template v-else>
                <FontAwesomeIcon
                  icon="image"
                  size="6x" />
              </template>
            </template>
          </drop>

          <div class="actions">
            <ButtonTiny
              @click="$refs.config.openConfig()">
              {{ $t('configure') }}
            </ButtonTiny>
          </div>
        </div>
      </div>
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <input
          ref="fileInput"
          class="file-input"
          type="file"
          @change="onFileChange">
        <div
          v-if="!showImages && !block.data.url">
          <div
            class="display-icon">
            <drop
              class="drop"
              @click.native="clickDrop"
              @dragover="dragOver = true"
              @dragleave="dragOver = false"
              @drop="handleDrop">
              <template v-if="dragOver">
                <FontAwesomeIcon
                  icon="cloud-upload-alt"
                  fixed-width />
              </template>
              <template
                v-else>
                <template v-if="uploading">
                  <FontAwesomeIcon
                    icon="circle-notch"
                    spin
                    fixed-width />
                </template>
                <template v-else>
                  <FontAwesomeIcon
                    icon="image"
                    fixed-width />
                </template>
              </template>
            </drop>
          </div>
          <div class="text-center mb-2">
            <template
              v-if="dragOver">
              {{ $t('drop-to-upload') }}
            </template>
            <template v-else>
              <template v-if="uploading">
                {{ $t('uploading') }}
              </template>
              <template v-else>
                {{ $t('drag-images-to-upload') }}
              </template>
            </template>
          </div>
        </div>

        <div
          v-if="showImages && listStyle"
          class="villain-image-library">
          <div class="col-12 mb-3">
            <ButtonSecondary @click="listStyle = false">
              {{ $t('show-thumbnails') }}
            </ButtonSecondary>
            <ButtonSecondary @click="showImages = false">
              {{ $t('hide-image-list') }}
            </ButtonSecondary>
          </div>
          <table
            class="table villain-image-table">
            <tr
              v-for="i in images"
              :key="i.id">
              <td class="fit">
                <img
                  :src="i.thumb"
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
          class="villain-image-library">
          <div class="col-12 mb-3">
            <ButtonSecondary @click="listStyle = true">
              {{ $t('show-image-list') }}
            </ButtonSecondary>
            <ButtonSecondary @click="showImages = false">
              {{ $t('hide-image-list') }}
            </ButtonSecondary>
          </div>
          <div
            v-for="i in images"
            :key="i.id"
            class="col-2">
            <img
              :src="i.thumb"
              class="img-fluid"
              @click="selectImage(i)" />
          </div>
        </div>

        <div v-else>
          <div class="panes">
            <div>
              <div v-if="block.data.url">
                <KInputToggle
                  v-model="advancedConfig"
                  name="config[advanced]"
                  :label="$t('show-advanced-config')" />

                <KInput
                  v-model="block.data.title"
                  name="data[title]"
                  :placeholder="$t('title')"
                  :label="$t('title')" />

                <KInput
                  v-model="block.data.alt"
                  name="data[alt]"
                  :placeholder="$t('alt')"
                  :help-text="$t('alt-help-text')"
                  :label="$t('alt')" />

                <KInput
                  v-model="block.data.credits"
                  name="data[credits]"
                  :placeholder="$t('credits')"
                  :label="$t('credits')" />

                <KInput
                  v-model="block.data.link"
                  name="data[link]"
                  :placeholder="$t('link')"
                  :label="$t('link')" />

                <div v-show="advancedConfig">
                  <KInput
                    v-model="block.data.url"
                    name="data[url]"
                    :placeholder="$t('url')"
                    :label="$t('url')" />

                  <KInputTextarea
                    v-model="block.data.media_queries"
                    name="data[media_queries]"
                    :label="$t('media_queries')" />

                  <KInputTextarea
                    v-model="block.data.srcset"
                    name="data[srcset]"
                    :label="$t('srcset')" />

                  <KInput
                    v-model="block.data.img_class"
                    name="data[img_class]"
                    :placeholder="$t('img_class')"
                    :label="$t('img_class')" />

                  <KInput
                    v-model="block.data.picture_class"
                    name="data[picture_class]"
                    :placeholder="$t('picture_class')"
                    :label="$t('picture_class')" />
                </div>
              </div>

              <div class="villain-config-content-buttons">
                <button
                  v-if="!showImages"
                  type="button"
                  class="btn btn-primary"
                  @click="getImages">
                  {{ $t('pick-from-library') }}
                </button>
                <button
                  v-if="block.data.url !== ''"
                  type="button"
                  class="btn btn-primary ml-3"
                  @click="resetImage">
                  {{ $t('reset-image-block') }}
                </button>
              </div>
            </div>
            <div
              v-if="block.data.url"
              class="shaded preview-image">
              <img
                v-if="block.data.url"
                :src="block.data.url"
                class="img-fluid" />
            </div>
          </div>
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'
import { Drop } from 'vue-drag-drop'

export default {
  name: 'PictureBlock',

  components: {
    Block,
    Drop
  },

  inject: [
    'urls',
    'headers',
    'available'
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
      advancedConfig: false,
      customClass: '',
      uid: null,
      showConfig: false,
      showImages: false,
      showUpload: false,
      images: [],
      originalUrl: '',
      dragOver: false,
      uploading: false,
      listStyle: false
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
    },
    previewUrl () {
      if (!this.block.data.sizes && !this.block.data.url) {
        return null
      }

      if (this.block.data.sizes.xlarge) {
        return this.block.data.sizes.xlarge
      } else {
        return this.block.data.url
      }
    }
  },

  methods: {
    clickDrop () {
      this.$refs.fileInput.click()
    },

    onFileChange (e) {
      if (e.target.files.length && e.target.files.length === 1) {
        this.upload(e.target.files[0])
      }
    },

    resetImage () {
      this.$set(this.block.data, 'url', '')
      this.$set(this.block.data, 'sizes', {})
      this.$set(this.block.data, 'credits', '')
      this.$set(this.block.data, 'title', '')
      this.$set(this.block.data, 'link', '')
      this.$set(this.block.data, 'dominant_color', null)
      this.$set(this.block.data, 'webp', false)
      this.$set(this.block.data, 'width', 0)
      this.$set(this.block.data, 'height', 0)
    },

    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
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
          this.showImages = true
        } else {
          this.$alerts.alertError(this.$t('error'), this.$t('empty-library'))
        }
      } catch (e) {
        this.$alerts.alertError(this.$t('error'), this.$t('library-connection-error'))
        console.error(e)
      }
    },

    selectImage (img) {
      this.showImages = false

      this.$set(this.block.data, 'url', img.src)
      this.$set(this.block.data, 'alt', img.alt)
      this.$set(this.block.data, 'sizes', img.sizes)
      this.$set(this.block.data, 'link', '')
      this.$set(this.block.data, 'credits', img.credits)
      this.$set(this.block.data, 'title', img.title)
      this.$set(this.block.data, 'webp', img.webp)
      this.$set(this.block.data, 'dominant_color', img.dominant_color)
      this.$set(this.block.data, 'width', img.width || 0)
      this.$set(this.block.data, 'height', img.height || 0)

      this.originalUrl = img.src
      this.showConfig = false
    },

    handleDrop (data, event) {
      event.preventDefault()
      this.$refs.block.openConfig()
      const files = event.dataTransfer.files

      if (files.length > 1) {
        this.$alerts.alertError(this.$t('error'), this.$t('max-one-image'))
        this.dragOver = false
        return false
      }

      const f = files.item(0)
      this.upload(f)
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
      formData.append('name', f.name)
      formData.append('slug', this.seriesSlug)
      formData.append('uid', this.createUID())

      try {
        this.dragOver = false
        this.uploading = true
        const response = await fetch(this.uploadURL, { headers, method: 'post', body: formData })
        const data = await response.json()
        if (data.status === 200) {
          this.showImages = false
          this.uploading = false

          this.$set(this.block.data, 'sizes', data.image.sizes)
          this.$set(this.block.data, 'credits', data.image.credits)
          this.$set(this.block.data, 'title', data.image.title)
          this.$set(this.block.data, 'alt', data.image.alt)
          this.$set(this.block.data, 'link', '')
          this.$set(this.block.data, 'url', data.image.src)
          this.$set(this.block.data, 'webp', data.image.webp)
          this.$set(this.block.data, 'dominant_color', data.image.dominant_color)
          this.$set(this.block.data, 'width', data.image.width || 0)
          this.$set(this.block.data, 'height', data.image.height || 0)

          this.originalUrl = data.image.src

          this.showConfig = false
        } else {
          this.uploading = false
          this.$alerts.alertError(this.$t('error'), this.$t('error-uploading-info', { error: data.error }))
        }
      } catch (e) {
        this.uploading = false
        this.$alerts.alertError(this.$t('error'), this.$t('error-uploading-info', { error: e }))
      }
    }
  }
}
</script>
<style lang="postcss" scoped>
  .villain-block-picture-caption {
    font-size: 10px;
    margin-top: 5px;

    span {
      font-weight: bold;
      margin-right: 5px;
      min-width: 70px;
      display: inline-block;
    }
  }

  .img-fluid {
    min-width: auto;
    max-width: 100%;
  }

  .preview-image {
    padding: 1rem;
  }

  .villain-image-library {
    display: flex;
    flex-wrap: wrap;
  }

  .mb-3 {
    margin-bottom: 15px;
  }

  input[type=file] {
    display: none;
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
</style>

<i18n>
  {
    "en": {
      "configure": "Configure image block",
      "grid": "Grid",
      "list": "List",
      "upload-images": "Upload image",
      "edit-captions": "Edit caption",
      "alt-text-help": "Image description for accessibility",
      "captions": "Captions",
      "drop-to-upload": "Drop to upload!",
      "uploading": "Uploading",
      "drag-images-to-upload": "Click or drag and drop your wanted images here",
      "pick-from-library": "Pick image from library",
      "error": "Error",
      "error-uploading": "Error uploading :(",
      "error-uploading-info": "Error uploading :(\n\n{error}",
      "show-thumbnails": "Show thumbnails",
      "show-image-list": "Show list view",
      "hide-image-list": "Hide list view",
      "show-advanced-config": "Show advanced configuration opts",
      "title": "Title",
      "alt": "Alt. text",
      "credits": "Credits",
      "link": "Image should link to",
      "url": "Source (advanced)",
      "media_queries": "Media queries (advanced)",
      "srcset": "Srcset (advanced)",
      "img_class": "CSS classes (img)",
      "picture_class": "CSS classes (picture)",
      "reset-image-block": "Reset image block",
      "empty-library": "No images found in library. Upload one instead!",
      "library-connection-error": "Failed connecting to image library!",
      "max-one-image": "You can max upload ONE image to the image block."
    },
    "no": {
      "configure": "Konfigurér bildeblokk",
      "grid": "Grid",
      "list": "List",
      "upload-images": "Last opp bilde",
      "edit-captions": "Endre bildetekster",
      "alt-text-help": "Beskrivelse av bildet for universell utforming",
      "captions": "Bildetekster",
      "drop-to-upload": "Slipp for å laste opp!",
      "uploading": "Laster opp",
      "drag-images-to-upload": "Klikk, eller dra bildet du vil laste opp hit",
      "pick-from-library": "Velg bilde fra bildebibliotek",
      "error": "Feil",
      "error-uploading": "Feil ved opplasting :(",
      "error-uploading-info": "Feil ved opplasting :(\n\n{error}",
      "show-thumbnails": "Vis thumbnails",
      "show-image-list": "Vis listevisning",
      "hide-image-list": "Skjul bildeliste",
      "show-advanced-config": "Vis avansert konfigurasjon",
      "title": "Tittel",
      "alt": "Alt. tekst",
      "credits": "Krediteringer",
      "link": "Bildet linker til",
      "url": "Kilde (avansert)",
      "media_queries": "Media queries (avansert)",
      "srcset": "Srcset (avansert)",
      "img_class": "CSS klasser (img)",
      "picture_class": "CSS klasser (picture)",
      "reset-image-block": "Nullstill bildeblokk",
      "empty-library": "Fant ingen bilder i biblioteket. Last opp et i stedet!",
      "library-connection-error": "Klarte ikke koble til bildebiblioteket!",
      "max-one-image": "Du kan kun laste opp ett bilde til denne blokken."
    }
  }
</i18n>
