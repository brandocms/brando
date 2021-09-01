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
      <KInput
        v-model="block.data.value"
        :label="block.data.label"
        :placeholder="block.data.placeholder"
        :help-text="block.data.help_text"
        name="data[value]" />
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <KInput
          v-model="block.data.label"
          :label="$t('label')"
          :placeholder="$t('label')"
          name="data[label]" />

        <KInput
          v-model="block.data.placeholder"
          :label="$t('placeholder')"
          :placeholder="$t('placeholder')"
          name="data[placeholder]" />

        <KInput
          v-model="block.data.help_text"
          :label="$t('help-text')"
          :placeholder="$t('help-text')"
          name="data[help_text]" />
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'InputBlock',

  components: {
    Block
  },

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
      uid: null
    }
  }
}
</script>

<i18n>
  {
    "en": {
      "label": "Label",
      "placeholder": "Placeholder",
      "help-text": "Help text"
    },
    "no": {
      "label": "Etikett",
      "placeholder": "Plassholder",
      "help-text": "Hjelpetekst"
    }
  }
</i18n>
