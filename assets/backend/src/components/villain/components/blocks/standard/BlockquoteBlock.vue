<template>
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
    <KInputTextarea
      v-model="block.data.text"
      :label="$t('quote')"
      name="data[text]" />
    <KInput
      v-model="block.data.cite"
      :label="$t('quote-author')"
      name="data[cite]" />
  </Block>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'BlockquoteBlock',

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
      customClass: '',
      uid: null
    }
  }
}
</script>
<i18n>
  {
    "en": {
      "quote": "Quote",
      "quote-author": "Quote author"
    },
    "no": {
      "quote": "Sitat",
      "quote-author": "Sitatforfatter"
    }
  }
</i18n>
