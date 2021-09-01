<template>
  <div>
    <Block
      :block="block"
      :parent="null"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <!-- parse each block inside columns -->
      <div class="row">
        <div
          v-for="col in block.data"
          :key="col.uid"
          :class="col.class">
          <div v-if="col.data.length">
            <div class="villain-block-container">
              <div class="villain-block-wrapper">
                <VillainPlus
                  :parent="col.uid"
                  @add="$emit('add', $event)"
                  @move="$emit('move', $event)" />
              </div>
            </div>
            <transition-group name="bounce">
              <div
                v-for="b in col.data"
                :key="b.uid"
                class="villain-block-container">
                <component
                  :is="b.type + 'Block'"
                  :block="b"
                  :parent="col.uid"
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
                  :parent="col.uid"
                  @add="$emit('add', $event)"
                  @move="$emit('move', $event)" />
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="helpful-actions">
        <ButtonTiny
          @click="$refs.config.openConfig()">
          Konfigurér kolonner
        </ButtonTiny>
      </div>
    </Block>
    <BlockConfig
      ref="config">
      <template #default>
        <div class="form-group">
          <KInput
            v-model="columnCount"
            label="Antall kolonner"
            name="data[columnCount]" />
          <ButtonSecondary @click="updateColumns">
            Sett kolonneantall (overskriver nåværende kolonner!)
          </ButtonSecondary>
          <template v-if="block.data.length">
            <label class="mt-4">Kolonne CSS-klasser (avansert)</label>
            <KInput
              v-for="(b, idx) in block.data"
              :key="b.uid"
              v-model="b.class"
              label=""
              :name="'data[class][' + idx + ']'"
              :class="idx > 0 ? 'mt-2' : ''" />
          </template>
          <div class="text-center mt-3">
          </div>
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import systemComponents from '../system'
import standardComponents from '.'

export default {
  name: 'ColumnsBlock',

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
      columnCount: 2,
      showConfig: false,
      uid: null
    }
  },

  created () {
    if (!this.block.data.length) {
      this.showConfig = true
    }
  },

  methods: {
    updateColumns () {
      let colClass
      this.block.data = []

      switch (parseInt(this.columnCount)) {
        case 1:
          colClass = 'col-12'
          break
        case 2:
          colClass = 'col-6'
          break
        case 3:
          colClass = 'col-4'
          break
        case 4:
          colClass = 'col-3'
          break
      }

      for (let i = 0; i < this.columnCount; i++) {
        this.addColumn(colClass)
      }

      this.showConfig = false
    },

    addColumn (colClass) {
      this.block.data.push({
        uid: this.createUID(),
        class: colClass,
        data: []
      })
    },

    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    }
  }
}
</script>
