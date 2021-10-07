<template>
  <Block
    :block="block"
    :parent="parent"
    class="villain-extra-padding"
    @add="$emit('add', $event)"
    @move="$emit('move', $event)"
    @delete="$emit('delete', $event)"
    @duplicate="$emit('duplicate', $event)"
    @hide="$emit('hide', $event)"
    @show="$emit('show', $event)"
    @toggle-config="showConfig = $event">
    <KInputCode
      v-model="block.data.text"
      label=""
      transparent
      name="data[text]" />
    <template slot="help">
      <p>
        Markdown formatering er en ryddig måte å formatere tekst til nettsider på.
        Her er noen av de vanligste formatene du kan bruke i denne blokka:
      </p>
      <code>*Kursiv tekst*</code> &rarr; <em>Kursiv tekst</em><br>
      <code>**Uthevet tekst**</code> &rarr; <strong>Uthevet tekst</strong><br>
      <code>[Lenke-tekst](https://www.nrk.no)</code> &rarr; <a href="https://nrk.no">Lenke-tekst</a><br>
    </template>
  </Block>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'MarkdownBlock',

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
      codeMirror: null
    }
  },

  destroy () {
    // garbage cleanup
    const element = this.codeMirror.doc.cm.getWrapperElement()
    element && element.remove && element.remove()
  }
}
</script>
