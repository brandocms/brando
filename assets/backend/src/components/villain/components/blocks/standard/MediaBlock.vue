<template>
  <Block
    v-if="!block.data.type"
    :block="block"
    :parent="parent"
    @add="$emit('add', $event)"
    @move="$emit('move', $event)"
    @duplicate="$emit('duplicate', $event)"
    @hide="$emit('hide', $event)"
    @show="$emit('show', $event)"
    @delete="$emit('delete', $event)">
    <div class="villain-block-media">
      <div
        class="villain-block-media-empty">
        <div class="choose">
          {{ $t('pick') }}
        </div>
        <div class="actions">
          <ButtonTiny
            v-for="(component, idx) in block.data.available_components"
            :key="idx"
            @click="selectComponent(component)">
            {{ getComponentName(component) }}
          </ButtonTiny>
        </div>
      </div>
    </div>
  </Block>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'MediaBlock',

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

    mref: {
      type: String,
      default: null
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
      showConfig: false
    }
  },

  methods: {
    getComponentName ({ component }) {
      const foundBlock = this.available.blocks.find(b => b.component === component)
      if (foundBlock) {
        return foundBlock.name
      }
      return '--'
    },

    selectComponent ({ component, dataTemplate }) {
      const foundBlock = this.available.blocks.find(b => b.component === component)
      if (foundBlock) {
        const newBlock = {
          type: foundBlock.component.toLowerCase(),
          data: { ...foundBlock.dataTemplate, ...dataTemplate }
        }
        if (this.$parent.$options.name === 'BuiltComponent') {
          // in a ModuleBlock
          this.$parent.replace({ mref: this.mref, newBlock })
        } else {
          // a freestanding MediaBlock
          this.$set(this.block, 'type', foundBlock.component.toLowerCase())
          this.$set(this.block, 'data', { ...foundBlock.dataTemplate, ...dataTemplate })
        }
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

  .choose {
    text-align: center;
    margin-bottom: 15px;
  }

  .actions {
    display: flex;
    justify-content: center;

    button {
      @space margin-x 2px;
    }
  }
</style>
<i18n>
  {
    "en": {
      "pick": "Choose media type for this block"
    },
    "no": {
      "pick": "Velg medietype for blokken"
    }
  }
</i18n>
