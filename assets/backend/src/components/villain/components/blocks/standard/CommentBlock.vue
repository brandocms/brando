<template>
  <Block
    :block="block"
    :parent="parent"
    @add="$emit('add', $event)"
    @move="$emit('move', $event)"
    @duplicate="$emit('duplicate', $event)"
    @hide="$emit('hide', $event)"
    @show="$emit('show', $event)"
    @delete="$emit('delete', $event)">
    <template #description></template>
    <div class="villain-block-comment">
      <KInputCode
        v-model="block.data.text"
        transparent
        :line-numbers="false"
        name="data[text]"
        :label="$t('comment')" />
    </div>
  </Block>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'CommentBlock',

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
      uid: null,
      showConfig: false
    }
  },

  methods: {
    handleInput (e) {
      const start = e.target.selectionStart
      this.$nextTick(() => {
        e.target.selectionStart = e.target.selectionEnd = start
      })
    }
  }
}
</script>

<style lang="postcss" scoped>
  >>> textarea {
    background-color: transparent;
  }
</style>

<i18n>
  {
    "en": {
      "comment": "Comment"
    },
    "no": {
      "comment": "Kommentar"
    }
  }
</i18n>
