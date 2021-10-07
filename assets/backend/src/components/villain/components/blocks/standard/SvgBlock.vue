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
      <div class="villain-block-svg">
        <div
          v-if="block.data.code"
          ref="svg"
          class="villain-svg-output"
          v-html="block.data.code">
        </div>
        <div
          v-else
          class="villain-block-svg-empty">
          <FontAwesomeIcon
            icon="draw-polygon"
            size="6x" />
        </div>
        <div class="helpful-actions">
          <ButtonTiny
            @click="$refs.config.openConfig()">
            {{ $t('configure') }}
          </ButtonTiny>
        </div>
      </div>
    </Block>

    <BlockConfig
      ref="config"
      v-model="block.data">
      <template #default="{ cfg }">
        <KInputCode
          v-model="cfg.code"
          name="data[code]"
          :label="$t('code')" />

        <KInput
          v-model="cfg.class"
          name="data[class]"
          :label="$t('css-classes')" />
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'SvgBlock',

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
      uid: null,
      showConfig: false
    }
  }
}
</script>

<style lang="postcss" scoped>
  .villain-block-svg {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .villain-block-svg-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;

    svg {
      height: auto;
      max-width: 250px;
    }
  }

  .villain-svg-output {
    >>> svg {
      width: 100%;
      height: 100%;
      max-width: 500px;
    }
  }
</style>

<i18n>
  {
    "en": {
      "configure": "Configure SVG",
      "code": "Code",
      "css-classes": "CSS classes"
    },
    "no": {
      "configure": "Konfigurér SVG",
      "code": "Kode",
      "css-classes": "CSS-klasser"
    }
  }
</i18n>
