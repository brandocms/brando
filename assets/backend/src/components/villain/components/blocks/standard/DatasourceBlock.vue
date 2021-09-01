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
      <div class="villain-block-datasource-info">
        <FontAwesomeIcon
          icon="database"
          size="6x"
          fixed-width />
        <div
          v-if="block.data.module"
          class="inside">
          <p>{{ $t('datasource') }} — {{ block.data.description }}</p>
          <p><small><code>{{ block.data.module }}<br>{{ block.data.type }}|{{ block.data.query }}</code></small></p>
          <div v-if="block.data.type === 'selection'">
            <ButtonPrimary
              class="mt-2"
              @click="selectEntries">
              {{ $t((block.data.limit && parseInt(block.data.limit) === 1) ? 'pick-entry' : 'pick-entries') }}
            </ButtonPrimary>
            <template v-if="selectedEntries.length">
              <transition-group
                v-sortable="{handle: '.sort-handle', animation: 0, store: {get: getOrder, set: storeOrder}}"
                name="fade-move"
                tag="div"
                class="sort-container">
                <div
                  v-for="e in selectedEntries"
                  :key="e.id"
                  :data-id="e.id"
                  class="selected-entry sort-handle">
                  #{{ e.id }} — {{ e.label }}
                </div>
              </transition-group>
            </template>
          </div>
        </div>
      </div>
      <div class="helpful-actions">
        <ButtonTiny
          @click="openConfig">
          {{ $t('configure') }}
        </ButtonTiny>
      </div>
      <BlockConfig
        ref="config">
        <template #default>
          <div class="panes">
            <div>
              <KInput
                v-model="block.data.description"
                rules="required"
                name="data[description]"
                :label="$t('description')"
                :placeholder="$t('description.placeholder')" />

              <KInputRadios
                v-model="block.data.module"
                rules="required"
                :options="availableDatasources"
                option-value-key="module"
                option-label-key="module"
                name="data[module]"
                :label="$t('module')" />

              <KInputRadios
                v-model="block.data.type"
                rules="required"
                :options="availableDatasourceTypes"
                name="data[type]"
                :label="$t('type')" />

              <KInputRadios
                v-model="block.data.query"
                rules="required"
                :options="availableDatasourceQueries"
                name="data[query]"
                :label="$t('query')" />

              <KInput
                v-model="block.data.arg"
                name="data[arg]"
                :label="$t('argument')" />

              <KInputSelect
                v-model="block.data.module_id"
                :options="modules"
                option-value-key="id"
                option-label-key="name"
                name="data[module_id]"
                :label="$t('module')" />

              <KInputNumber
                v-if="block.data.type === 'selection'"
                v-model="block.data.limit"
                name="data[limit]"
                :label="$t('limit')" />
            </div>
            <div></div>
          </div>
          <KInputCode
            v-model="block.data.code"
            :label="$t('template')"
            name="data[code]" />
        </template>
      </BlockConfig>
      <KModal
        v-if="showAvailableEntries"
        ref="availableEntriesModal"
        v-shortkey="['esc', 'enter']"
        :ok-text="$t('close')"
        @shortkey.native="closeAvailableEntriesModal"
        @ok="closeAvailableEntriesModal">
        <template #header>
          {{ $t((block.data.limit && parseInt(block.data.limit) === 1) ? 'pick-entry' : 'pick-entries') }}
        </template>
        <ButtonSecondary
          @click="reset">
          {{ $t('reset-entries') }}
        </ButtonSecondary>
        <ContentList
          :selectable="false"
          :tools="false"
          :entries="availableEntries">
          <template #row="{ entry }">
            <div
              class="row-wrap"
              :class="{selected: block.data.ids.includes(parseInt(entry.id))}">
              <div>#{{ entry.id }} — {{ entry.label }}</div>

              <ButtonTiny
                v-if="!block.data.ids.includes(parseInt(entry.id))"
                @click="addSelectedEntry(entry.id)">
                {{ $t('add') }}
              </ButtonTiny>
              <ButtonTiny
                v-else
                @click="removeSelectedEntry(entry.id)">
                {{ $t('remove') }}
              </ButtonTiny>
            </div>
          </template>
        </ContentList>
      </KModal>
    </block>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'DatasourceBlock',

  components: {
    Block
  },

  inject: [
    'urls',
    'headers',
    'available',
    'adminChannel'
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
      showConfig: false,
      showAvailableEntries: false,
      availableEntries: [],
      availableDatasources: [],
      availableDatasourceKeys: [],
      availableDatasourceTypes: [],
      availableDatasourceQueries: [],
      selectedEntries: [],
      modules: []
    }
  },

  watch: {
    'block.data.module' (val) {
      this.getDatasourceKeys(val)
    },

    'block.data.type' (val) {
      this.getDatasourceQueries(val)
    },

    'block.data.arg' (val) {
      if (val === '') {
        this.block.data.arg = null
      }
    }
  },

  async created () {
    this.getDatasources()
    this.getTemplates()

    if (this.block.data.module) {
      this.getDatasourceKeys()
    }

    if (this.block.data.ids.length) {
      await this.listAvailableEntries()
      this.refreshSelectedEntries()
    }
  },

  methods: {
    openConfig () {
      this.$refs.config.openConfig()
    },

    refreshSelectedEntries () {
      this.selectedEntries = this.block.data.ids.map(id => this.availableEntries.find(e => parseInt(e.id) === parseInt(id)))
    },

    getOrder (sortable) {
      return this.block.data.ids
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray().map(Number)
      this.block.data.ids = this.sortedArray
    },

    getDatasources () {
      this.adminChannel.channel
        .push('datasource:list_datasources', {})
        .receive('ok', payload => {
          this.availableDatasources = payload.available_datasources
        })
    },

    getTemplates () {
      this.adminChannel.channel
        .push('datasource:list_modules')
        .receive('ok', payload => {
          this.modules = payload.modules
        })
    },

    getDatasourceKeys () {
      this.adminChannel.channel
        .push('datasource:list_datasource_keys', { module: this.block.data.module })
        .receive('ok', payload => {
          this.availableDatasourceKeys = payload.available_datasource_keys
          this.availableDatasourceTypes = Object.keys(payload.available_datasource_keys).map(t => ({ name: t, value: t }))
          if (this.block.data.type) {
            this.availableDatasourceQueries = this.availableDatasourceKeys[this.block.data.type].map(t => ({ name: t, value: t }))
          }
        })
    },

    getDatasourceQueries (val) {
      this.availableDatasourceQueries = this.availableDatasourceKeys[val].map(t => ({ name: t, value: t }))
    },

    selectEntries () {
      this.listAvailableEntries()
      this.showAvailableEntries = true
    },

    listAvailableEntries () {
      return new Promise((resolve, reject) => {
        this.adminChannel.channel
          .push('datasource:list_available_entries', { module: this.block.data.module, query: this.block.data.query })
          .receive('ok', payload => {
            this.availableEntries = payload.available_entries
            if (!this.block.data.ids) {
              this.block.data = {
                ...this.block.data,
                ids: []
              }
            }
            resolve()
          })
      })
    },

    async closeAvailableEntriesModal () {
      await this.$refs.availableEntriesModal.close()
      this.showAvailableEntries = false
      this.refreshSelectedEntries()
    },

    addSelectedEntry (id) {
      if (this.block.data.limit) {
        if (this.block.data.ids.length >= this.block.data.limit) {
          this.$alerts.alertError(this.$t('error'), this.$t('error-max', { limit: this.block.data.limit }))
          return
        }
      }

      this.block.data.ids.push(id)

      if (this.block.data.limit) {
        // close modal when limit is hit
        if (this.block.data.ids.length === parseInt(this.block.data.limit)) {
          this.closeAvailableEntriesModal()
        }
      }
    },

    removeSelectedEntry (id) {
      const newIds = this.block.data.ids.filter(i => i !== id)
      this.$set(this.block.data, 'ids', newIds)
      this.refreshSelectedEntries()
    },

    reset () {
      this.$set(this.block.data, 'ids', [])
      this.refreshSelectedEntries()
    },

    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    }
  }
}
</script>

<style lang="postcss" scoped>
  .helpful-actions {
    justify-content: center;
  }

  .row-wrap {
    display: flex;
    width: 100%;
    justify-content: space-between;
  }

  .villain-block-datasource-info,
  .villain-block-datasource-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;

    .inside {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
    }

    svg {
      margin-bottom: 25px;
    }
  }

  .selected-entry {
    margin-top: 15px;
    padding: 7px 0;
    border-bottom: 1px solid theme(colors.peach);
  }
</style>
<i18n>
  {
    "en": {
      "datasource": "Datasource",
      "pick-entries": "Select entries",
      "pick-entry": "Select entry",
      "reset-entries": "Reset",
      "configure": "Configure datasource",
      "description": "Description",
      "description.placeholder": "Description of datasource",
      "module": "Source module",
      "type": "Type",
      "query": "Query",
      "argument": "Argument",
      "limit": "Limit",
      "module": "Module for datasource",
      "close": "Close",
      "add": "Add",
      "remove": "Remove",
      "error": "Error",
      "error-max": "Cannot select more than {limit} entries"
    },
    "no": {
      "datasource": "Datakilde",
      "pick-entries": "Velg oppføringer",
      "pick-entry": "Velg oppføring",
      "reset-entries": "Nullstill",
      "configure": "Konfigurér datakilde",
      "description": "Beskrivelse",
      "description.placeholder": "Beskrivelse av datakilden",
      "module": "Kildemodul",
      "type": "Type",
      "query": "Spørring",
      "argument": "Argument",
      "limit": "Maks antall",
      "template": "Mal for datakilden",
      "close": "Lukk",
      "add": "Legg til",
      "remove": "Fjern",
      "error": "Feil",
      "error-max": "Kan kun velge {limit} oppføringer"
    }
  }
</i18n>
