<template>
  <div
    class="villain-container-block"
    :data-class="block.data.class">
    <Block
      :block="block"
      :parent="null"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <template #description>
        <span :style="{ color, marginLeft: '5px' }">⬤</span> {{ block.data.description }}
      </template>
      <section :b-section="block.data.class">
        <div v-if="block.data.blocks.length">
          <div class="villain-block-container">
            <div class="villain-block-wrapper">
              <VillainPlus
                :parent="block.uid"
                @add="$emit('add', $event)"
                @move="$emit('move', $event)" />
            </div>
          </div>
          <transition-group name="bounce">
            <div
              v-for="b in block.data.blocks"
              :key="b.uid"
              class="villain-block-container">
              <component
                :is="b.type + 'Block'"
                :block="b"
                :parent="block.uid"
                :after="b.uid"
                @add="$emit('add', $event)"
                @move="$emit('move', $event)"
                @hide="$emit('hide', $event)"
                @show="$emit('show', $event)"
                @delete="$emit('delete', $event)" />
            </div>
          </transition-group>
        </div>
        <div v-else>
          <div class="villain-block-container">
            <div class="villain-block-wrapper">
              <VillainPlus
                :parent="block.uid"
                @add="$emit('add', $event)"
                @move="$emit('move', $event)" />
            </div>
          </div>
        </div>
      </section>

      <div class="helpful-actions">
        <ButtonTiny
          @click="$refs.config.openConfig()">
          Seksjonoppsett
        </ButtonTiny>
      </div>
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <KInput
          v-model="block.data.description"
          name="data[description]"
          :label="$t('description')" />
        <KInputRadios
          v-model="block.data.class"
          :options="availableSections"
          option-value-key="value"
          option-label-key="label"
          name="data[class]"
          :label="$t('class')" />

        <KInputCode
          ref="wrapper"
          v-model="block.data.wrapper"
          name="data[wrapper]"
          :label="$t('wrapper')" />
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import systemComponents from '../system'
import standardComponents from '.'

export default {
  name: 'ContainerBlock',

  components: {
    ...systemComponents,
    ...standardComponents
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
      showConfig: false,
      uid: null
    }
  },

  computed: {
    color () {
      const section = this.availableSections.find(c => c.value === this.block.data.class)
      return section.color
    }
  },

  watch: {
    'block.data.class' (val) {
      const section = this.availableSections.find(c => c.value === this.block.data.class)
      this.$set(this.block.data, 'wrapper', section.wrapper)
      this.$nextTick(() => {
        this.$refs.wrapper.refreshEditor(section.wrapper)
      })
    }
  },

  created () {
    this.availableSections = this.$app.sections || [{ label: 'Standard', value: 'standard', color: '#000' }]
  },

  methods: {
    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    }
  }
}
</script>
<i18n>
  {
    "en": {
      "class": "Section class",
      "description": "Section description"
    },
    "no": {
      "class": "Seksjonstype",
      "description": "Seksjonsbeskrivelse"
    }
  }
</i18n>
