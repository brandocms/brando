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
      <div
        v-if="!block.data.rows"
        class="villain-block-empty">
        <i class="fa fa-fw fa-table"></i>
        <div class="actions">
          <ButtonSecondary
            @click="$refs.config.openConfig()">
            {{ $t('configure') }}
          </ButtonSecondary>
        </div>
      </div>
      <div
        v-else
        class="table-wrapper">
        <transition-group
          v-sortable="{handle: '.villain-block-datatable-item', animation: 0, store: {get: getOrder, set: storeOrder}}"
          class="villain-block-datatable"
          name="fade-move"
          tag="table">
          <tr
            v-for="item in block.data.rows"
            :key="item.id"
            :data-id="item.id"
            class="villain-block-datatable-item">
            <td class="villain-block-datatable-item-key">
              {{ item.key }}
            </td>
            <td class="villain-block-datatable-item-value">
              {{ item.value }}
            </td>
          </tr>
        </transition-group>
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
      v-model="block.data"
      @close="forceUpdate">
      <template #default="{ cfg }">
        <KInputTable
          v-model="cfg.rows"
          name="data[data]"
          label="Datatabell"
          :sortable="true"
          :delete-rows="true"
          :add-rows="false">
          <template #row="{ entry }">
            <td>
              <div class="mt-2 mb-2">
                <KInput
                  v-model="entry.key"
                  compact
                  name="entry[key]"
                  :placeholder="$t('key')"
                  label="" />
              </div>

              <div class="mb-2">
                <KInput
                  v-model="entry.value"
                  compact
                  name="entry[value]"
                  :placeholder="$t('value')"
                  label="" />
              </div>
            </td>
          </template>
        </KInputTable>

        <div class="d-flex justify-content-center">
          <ButtonSecondary
            @click="addItem(cfg)">
            {{ $t('add-line') }}
          </ButtonSecondary>
        </div>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'DatatableBlock',

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
      customClass: '',
      uid: null,
      showConfig: false
    }
  },

  methods: {
    forceUpdate (data) {
      this.$set(this.block, 'data', data)
    },

    getOrder (sortable) {
      return this.block.data.rows
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray()
      let newOrder = []
      this.sortedArray.forEach(id => {
        const i = this.block.data.rows.find(i => {
          return i.id === id
        })

        if (i) {
          newOrder = [
            ...newOrder,
            i
          ]
        }
      })

      this.$set(this.block.data, 'rows', newOrder)
    },

    addItem (cfg) {
      cfg.rows = [
        ...cfg.rows,
        { id: this.$utils.guid(), key: this.$t('key'), value: this.$t('value') }
      ]
    }
  }
}
</script>

<style lang="postcss" scoped>
  .table-wrapper {
    margin: 0 auto;
  }

  .villain-block-datatable {
    margin: 0 auto;

    .villain-block-datatable-item {
      padding: 0 2rem;

      &:hover {
        cursor: move;
      }

      .villain-block-datatable-item-key {
        font-weight: 500;
        padding-right: 2rem;
        text-align: right;
      }
      .villain-block-datatable-item-value {
        padding-left: 2rem;
        text-align: left;
      }
    }
  }

  .villain-block-config-content {
    table {
      margin-right: 0;
      width: 100%;
    }
    td button {
      margin-bottom: 15px;
      border: none;
      width: 35px;
      min-width: 35px;
    }
  }

  .desc {
    text-align: center;
    margin-bottom: 25px;
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

  .helpful-actions {
    justify-content: center;
  }

</style>
<i18n>
  {
    "en": {
      "configure": "Configure datatable",
      "key": "Key",
      "value": "Value",
      "add-line": "Add line"
    },
    "no": {
      "configure": "Konfigurér datatabell",
      "key": "Nøkkel",
      "value": "Verdi",
      "add-line": "Legg til ny linje"
    }
  }
</i18n>
