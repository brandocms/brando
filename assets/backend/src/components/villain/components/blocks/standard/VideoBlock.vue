<template>
  <div>
    <Block
      ref="block"
      :block="block"
      :parent="parent"
      :show-ok="true"
      icon="fa-video"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <div class="villain-block-video">
        <template
          v-if="html && block.data.source !== 'file'">
          <div
            ref="preview"
            class="villain-block-video-content"
            v-html="html" />
          <div class="helpful-actions">
            <ButtonTiny
              @click="$refs.config.openConfig()">
              {{ $t('configure') }}
            </ButtonTiny>
          </div>
        </template>
        <template
          v-else-if="html && block.data.source === 'file'">
          <div
            ref="preview"
            class="villain-block-video-file-content"
            v-html="html" />
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
          <FontAwesomeIcon
            :icon="['fab', 'youtube']"
            size="6x" />
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
      ref="config"
      v-model="block.data">
      <template #default>
        <div class="desc">
          {{ $t('paste-link') }} <br>
          I.e. <strong>https://www.youtube.com/watch?v=jlbunmCbTBA</strong>
        </div>
        <div>
          <KInput
            v-model="url"
            name="url"
            :label="$t('paste-link')"
            placeholder="https://www.youtube.com/watch?v=jlbunmCbTBA"
            @input="parseUrl" />

          <template
            v-if="block.data.remote_id">
            <KInput
              v-model="block.data.remote_id"
              name="data[remote_id]"
              disabled
              :label="$t('existing-data') + ` — ${block.data.source}`"
              placeholder="ID" />

            <KInput
              v-model="block.data.link"
              name="data[link]"
              :label="$t('link-video-to-url')"
              placeholder="google.com" />

            <KInput
              v-model="block.data.poster"
              name="data[poster]"
              :label="$t('poster-url')"
              placeholder="https://link.com/image.jpg" />
          </template>
        </div>
        <div v-if="block.data.url">
          <KInput
            v-model="block.data.class"
            name="data[class]"
            :label="$t('css-classes')"
            placeholder=".my-class .another-class" />
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

const VIMEO_REGEX = /(?:http[s]?:\/\/)?(?:www.)?vimeo.com\/(.+)/
const YOUTUBE_REGEX = /(?:youtube\.com\/\S*(?:(?:\/e(?:mbed))?\/|watch\?(?:\S*?&?v=))|youtu\.be\/)([a-zA-Z0-9_-]{6,11})/
const FILE_REGEX = /(.*)/

export default {
  name: 'VideoBlock',

  components: {
    Block
  },

  inject: ['available'],

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
      customClass: '',
      uid: null,
      url: '',
      html: '',

      providers: {
        vimeo: {
          regex: VIMEO_REGEX,
          html: [
            '<iframe src="{{protocol}}//player.vimeo.com/video/{{remote_id}}?title=0&byline=0" ',
            'width="580" height="320" frameborder="0"></iframe>'
          ].join('\n')
        },
        youtube: {
          regex: YOUTUBE_REGEX,
          html: ['<iframe src="{{protocol}}//www.youtube.com/embed/{{remote_id}}" ',
            'width="580" height="320" frameborder="0" allowfullscreen></iframe>'
          ].join('\n')
        },
        file: {
          regex: FILE_REGEX,
          html: ['<video class="villain-video-file" muted="muted" tabindex="-1" loop autoplay src="{{remote_id}}">',
            '<source src="{{remote_id}}" type="video/mp4">',
            '</video>'
          ].join('\n')
        }
      }
    }
  },

  created () {
    if (this.block.data.remote_id) {
      this.html = this.providers[this.block.data.source].html
        .replace('{{protocol}}', window.location.protocol)
        .replace('{{remote_id}}', this.block.data.remote_id)
    }
  },

  mounted () {
    this.$nextTick(() => {
      setTimeout(() => {
        if (this.$refs.preview) {
          const rect = this.$refs.preview.getBoundingClientRect()
          this.$set(this.block.data, 'width', Math.round(rect.width))
          this.$set(this.block.data, 'height', Math.round(rect.height))
        }
      }, 3500)
    })
  },

  updated () {
    console.debug('<VideoBlock /> updated')
  },

  methods: {
    parseUrl () {
      let match
      const url = this.url

      if (url.startsWith('https://player.vimeo.com/external/')) {
        this.$set(this.block.data, 'source', 'file')
        this.$set(this.block.data, 'remote_id', url)
        // this.showConfig = false
      } else {
        for (const key of Object.keys(this.providers)) {
          const provider = this.providers[key]
          match = provider.regex.exec(url)

          if (match !== null && match[1] !== undefined) {
            this.$set(this.block.data, 'source', key)
            this.$set(this.block.data, 'remote_id', match[1])
            if (key !== 'file') {
              // this.showConfig = false
            }
            break
          }
        }

        if (!{}.hasOwnProperty.call(this.providers, this.block.data.source)) {
          return false
        }
      }

      this.html = this.providers[this.block.data.source].html
        .replace('{{protocol}}', window.location.protocol)
        .replace('{{remote_id}}', this.block.data.remote_id)
    }
  }
}
</script>
<style lang="postcss" scoped>
  .disabled {
    background-color: lightgrey;
  }

  .desc {
    margin-bottom: 25px;
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

  .drop {
    background-color: white;
    margin-bottom: 20px;
  }
</style>

<i18n>
  {
    "en": {
      "configure": "Configure video block",
      "paste-link": "Paste URL to youtube, vimeo or external file.",
      "existing-data": "Existing data",
      "link-video-to-url": "Link video to URL",
      "poster-url": "URL for poster",
      "css-classes": "Extra CSS classes"
    },
    "no": {
      "configure": "Konfigurér videoblokk",
      "paste-link": "Lim inn link til youtube, vimeo eller ekstern fil.",
      "existing-data": "Eksisterende data",
      "link-video-to-url": "Link video til denne URL",
      "poster-url": "URL for posterbilde",
      "css-classes": "Ekstra CSS-klasser"
    }
  }
</i18n>
