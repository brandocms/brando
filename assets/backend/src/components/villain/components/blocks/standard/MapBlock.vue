<template>
  <div>
    <Block
      ref="block"
      :block="block"
      :parent="parent"
      icon="fa-compass"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <div class="villain-block-video">
        <div
          v-if="html"
          class="villain-block-video-content"
          v-html="html" />
        <div
          v-else
          class="villain-block-empty">
          <i class="fa fa-fw fa-map"></i>
        </div>
        <div class="actions">
          <ButtonTiny
            @click="$refs.config.openConfig()">
            {{ $t('configure') }}
          </ButtonTiny>
        </div>
      </div>
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <div
          class="form-group">
          <KInput
            v-model="url"
            name="url"
            :label="$t('url')"
            :help-text="$t('url-help-text')"
            @input="parseUrl" />
        </div>
        <div
          v-if="block.data.url"
          class="form-group">
          <KInput
            v-model="block.data.class"
            name="data[class]"
            :label="$t('css-classes')" />
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'MapBlock',

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
      showConfig: false,
      url: '',
      html: '',
      providers: {
        gmaps: {
          regex: /<iframe(?:.*)src="(.*?)"/,
          html: `
            <iframe src="https://{{embed_url}}"
                    width="600"
                    height="450"
                    frameborder="0"
                    style="border:0"
                    allowfullscreen></iframe>`
        }
      }
    }
  },

  created () {
    if (this.block.data.embed_url) {
      this.populateMap()
    }
  },

  methods: {
    parseUrl (v) {
      let match
      const url = this.url

      for (const key of Object.keys(this.providers)) {
        const provider = this.providers[key]
        match = provider.regex.exec(url)

        if (match !== null && match[1] !== undefined) {
          this.block.data.source = key
          this.block.data.embed_url = match[1].replace('http:', '').replace('https:', '')
        }
      }

      this.populateMap()
    },

    populateMap () {
      if (!{}.hasOwnProperty.call(this.providers, this.block.data.source)) {
        return false
      }

      this.html = this.providers[this.block.data.source].html
        .replace('{{embed_url}}', this.block.data.embed_url)
    }
  }
}
</script>

<style lang="postcss" scoped>
  .actions {
    margin-top: 15px;
    text-align: center;
  }

  .villain-block-empty {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;

    svg {
      width: 30%;
      height: 30%;
      max-width: 250px;
      margin-bottom: 25px;
    }
  }
</style>

<i18n>
  {
    "en": {
      "configure": "Configure map block",
      "url": "URL",
      "url-help-text": "Paste embed-link from Google Maps",
      "css-classes": "CSS classes"
    },
    "no": {
      "configure": "Konfigurér kartblokk",
      "url": "URL",
      "url-help-text": "Lim inn embed-link fra Google Maps",
      "css-classes": "CSS klasser"
    }
  }
</i18n>
