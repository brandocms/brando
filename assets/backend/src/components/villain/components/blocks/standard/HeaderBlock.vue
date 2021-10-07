<template>
  <div>
    <Block
      :block="block"
      :parent="parent"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <template #description>
        (H{{ block.data.level }})
      </template>
      <textarea
        ref="txt"
        v-model="block.data.text"
        rows="1"
        :style="'font-size: ' + fontSize + 'rem'"
        class="villain-header-input">
      </textarea>
      <div class="helpful-actions">
        <ButtonTiny
          @click="$refs.config.openConfig()">
          {{ $t('configure') }}
        </ButtonTiny>
      </div>
    </Block>
    <BlockConfig
      ref="config"
      v-model="block.data">
      <template #default="{ cfg }">
        <KInputRadios
          v-model="cfg.level"
          name="data[level]"
          rules="required"
          :options="[
            { label: 'H1', value: 1 },
            { label: 'H2', value: 2 },
            { label: 'H3', value: 3 },
            { label: 'H4', value: 4 },
            { label: 'H5', value: 5 },
            { label: 'H6', value: 6 }
          ]"
          option-value-key="value"
          option-label-key="label"
          :label="$t('size')" />

        <KInput
          v-model="cfg.id"
          name="data[id]"
          label="Id"
          :help-text="$t('id-help-text')" />

        <KInput
          v-model="cfg.class"
          name="data[class]"
          :label="$t('css-classes')" />
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import autosize from 'autosize'
import Block from '../system/Block'

export default {
  name: 'HeaderBlock',

  components: {
    Block
  },

  inject: [
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
      showConfig: false,
      customClass: '',
      uid: null
    }
  },

  computed: {
    fontSize () {
      const level = parseInt(this.block.data.level)
      switch (level) {
        case 1:
          return 2.75
        case 2:
          return 2.5
        case 3:
          return 2.25
        case 4:
          return 2
        case 5:
          return 1.75
        case 6:
          return 0.75
        default:
          return 1
      }
    }
  },

  mounted () {
    autosize(this.$refs.txt)
  }
}
</script>

<i18n>
  {
    "en": {
      "configure": "Configure heading",
      "size": "Size",
      "id-help-text": "Can be used as link target (#id-name-here)",
      "css-classes": "CSS classes"
    },
    "no": {
      "configure": "Konfigurér overskrift",
      "size": "Størrelse",
      "id-help-text": "Kan brukes som lenkemål (#id-navn-her)",
      "css-classes": "CSS klasser"
    }
  }
</i18n>
