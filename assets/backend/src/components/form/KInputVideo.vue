<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :maxlength="maxlength"
    :help-text="helpText"
    :compact="compact"
    :value="innerValue">
    <template #default="{ provider }">
      <input
        :id="id"
        ref="input"
        type="hidden"
        :value="innerValue"
        :class="{ monospace, invert, inputVideo: true }"
        :placeholder="placeholder"
        :maxlength="maxlength"
        :name="name"
        :disabled="disabled"
        @input="onChange(provider, $event)">
    </template>
    <template #outsideValidator>
      <KModal
        v-if="open"
        ref="modal"
        v-shortkey="['esc']"
        ok-text="OK"
        @shortkey.native="toggle"
        @ok="toggle()">
        <template #header>
          {{ $t("edit-video-data") }}
        </template>
        <div>
          <KInput
            v-model="url"
            name="video[url]"
            :label="$t('paste-video-link')"
            help-text="i.e.: <code>https://vimeo.com/76979871</code>" />
        </div>
        <div
          v-for="(msg, idx) in messages"
          :key="idx"
          class="message">
          <span>&rarr;</span> {{ msg }}
        </div>
        <div
          ref="vimeoEmbed"
          class="video-embed" />
      </KModal>
      <div class="input-video-wrapper">
        <div class="preview">
          <span>{{ source }}</span>
          <div
            v-if="thumbnailUrl"
            class="thumbnail">
            <img :src="thumbnailUrl" />
          </div>
          <div class="remote-id">
            {{ remoteId }} ({{ width }}&times;{{ height }})
          </div>
        </div>
        <button
          class="button-edit"
          @click.self.prevent.stop="toggleFromButton">
          {{ open ? $t('close') : $t('edit') }}
        </button>
      </div>
    </template>
  </KFieldBase>
</template>

<script>

const VIMEO_REGEX = /(?:http[s]?:\/\/)?(?:www.)?vimeo.com\/(.+)/
const YOUTUBE_REGEX = /(?:youtube\.com\/\S*(?:(?:\/e(?:mbed))?\/|watch\?(?:\S*?&?v=))|youtu\.be\/)([a-zA-Z0-9_-]{6,11})/
const FILE_REGEX = /(.*)/
let pid = 0

export default {

  inject: [
    'adminChannel'
  ],
  props: {
    disabled: {
      type: Boolean,
      default: false
    },

    compact: {
      type: Boolean,
      default: false
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: false,
      default: null
    },

    maxlength: {
      type: Number,
      default: null
    },

    placeholder: {
      type: String,
      required: false,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    monospace: {
      type: Boolean,
      default: false
    },

    invert: {
      type: Boolean,
      default: false
    },

    name: {
      type: String,
      required: true
    },

    value: {
      type: Object,
      default: () => {}
    }
  },

  data () {
    pid += 1
    return {
      messages: [],
      elementId: `vimeo-player-${pid}`,
      url: '',
      open: false,
      innerValue: '',
      html: null,
      source: 'Ukjent',
      remoteId: null,
      width: null,
      height: null,
      thumbnailUrl: null,
      providers: {
        vimeo: {
          regex: VIMEO_REGEX,
          html: [
            '<iframe src="{{protocol}}//player.vimeo.com/video/{{remote_id}}?title=0&byline=0" ',
            'frameborder="0"></iframe>'
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

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    }
  },

  watch: {
    innerValue (value) {
      this.$emit('input', value)
    },

    value (value) {
      this.innerValue = value
    }
  },

  created () {
    if (this.value) {
      this.innerValue = this.value
      this.source = this.value.source
      this.remoteId = this.value.remoteId
      this.url = this.value.url
      this.width = this.value.width
      this.height = this.value.height
      this.thumbnailUrl = this.value.thumbnailUrl
    }
  },

  methods: {
    onChange (provider, event) {
      provider.validate(event)
    },

    toggleFromButton () {
      this.toggle()
    },

    async toggle () {
      if (!this.open) {
        this.open = true
      } else {
        await this.handleInput()
        await this.$refs.modal.close()
        this.open = false
      }
    },

    focus () {
      this.$refs.input.focus()
    },

    async handleInput () {
      let match
      const url = this.url

      this.messages.push(this.$t('analyze-link'))

      if (url.startsWith('https://player.vimeo.com/external/')) {
        this.source = 'file'
        this.remoteId = url
      } else {
        for (const key of Object.keys(this.providers)) {
          const provider = this.providers[key]
          match = provider.regex.exec(url)

          if (match !== null && match[1] !== undefined) {
            this.source = key
            this.remoteId = match[1]
            break
          }
        }
        if (!{}.hasOwnProperty.call(this.providers, this.source)) {
          return false
        }
      }

      this.html = this.providers[this.source].html
        .replace('{{protocol}}', window.location.protocol)
        .replace('{{remote_id}}', this.remoteId)

      // grab oEmbed via Brando
      if (this.source !== 'file') {
        this.adminChannel.channel
          .push('oembed:get', { source: this.source, url: this.url })
          .receive('ok', ({ result }) => {
            this.width = result.width
            this.height = result.height
            this.thumbnailUrl = result.thumbnail_url
            this.messages.push(`Dimensjoner er ${this.width}x${this.height}`)

            const input = {
              url: this.url,
              width: this.width,
              height: this.height,
              source: this.source,
              remoteId: this.remoteId,
              thumbnailUrl: this.thumbnailUrl
            }

            this.$emit('input', input)
          })
      }
    }
  }
}
</script>
<style lang="postcss" scoped>
  input {
    @fontsize base;
    padding-top: 12px;
    padding-bottom: 12px;
    padding-left: 65px;
    padding-right: 15px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;

    &.monospace {
      @fontsize base(0.8);
      font-family: theme(typography.families.mono);
      padding-bottom: 12px;
      padding-top: 16px;

      &::placeholder {
        @fontsize base(0.8);
        font-family: theme(typography.families.mono);
      }
    }

    &.invert {
      @color fg input;
      @color bg dark;
    }
  }

  .button-edit {
    @fontsize sm/1;
    border: 1px solid theme(colors.dark);
    padding: 8px 12px 10px;
    transition: all 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.input);
    }
  }

  .input-video-wrapper {
    position: relative;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-left: 15px;
    padding-right: 15px;
    height: 50px;
    width: 100%;
    background-color: #f6f6f6;
    border: 0;

    .preview {
      display: flex;
      align-items: center;

      span {
        @font mono 12px;
        @space padding-right 15px;
        text-transform: uppercase;
      }

      .thumbnail {
        @space padding-right 15px;
        width: 50px;
      }

      .remote-id {
        &:before {
          content: 'ID: '
        }
      }
    }

  }

  .video-embed {
    display: none;
  }

  .message {
    @font mono 12px;

    span {
      opacity: 0.7;
    }
  }
</style>

<i18n>
  {
    "en": {
      "edit-video-data": "Edit video data",
      "paste-video-link": "Paste video link",
      "close": "Close",
      "edit": "Edit",
      "analyze-link": "Analyzing link..."
    },
    "no": {
      "edit-video-data": "Endre videodata",
      "paste-video-link": "Lim inn link til video",
      "close": "Lukk",
      "edit": "Endre",
      "analyze-link": "Analyserer lenken..."
    }
  }
</i18n>
