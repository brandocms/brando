<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :help-text="helpText"
    :value="value">
    <template #default>
      <input
        :id="id"
        ref="input"
        v-model="innerValue"
        :placeholder="placeholder"
        :name="name"
        :disabled="disabled"
        type="hidden">
    </template>
    <template #outsideValidator>
      <KModal
        v-if="open"
        ref="modal"
        v-shortkey="['esc']"
        :ok-text="$t('close')"
        @shortkey.native="toggle"
        @ok="toggle()">
        <template #header>
          <span>{{ showCreateEntry ? createEntry : label }}</span>
          <div>
            <ButtonSecondary
              v-if="createEntry"
              @click="toggleCreateEntry">
              <template v-if="!showCreateEntry">
                + {{ createEntry }}
              </template>
              <template v-else>
                {{ $t('back-to-list') }}
              </template>
            </ButtonSecondary>
          </div>
        </template>

        <div
          v-if="!showCreateEntry"
          class="panes">
          <div
            ref="list"
            class="options"
            :style="{ maxHeight: optimizedHeight + 'px' }">
            <div
              class="megaselect__search"
              style="line-height: 1.5">
              <input
                ref="search"
                v-model="searchString"
                name="search"
                :placeholder="$t('search')"
                autocomplete="off"
                spellcheck="false"
                class="search"
                type="text"
                @keydown.enter.prevent="searchEnter"
                @keydown.down.prevent="pointerForward()"
                @keydown.up.prevent="pointerBackward()"
                @focus="$event.target.select()">
            </div>
            <div
              v-for="(option, index) in filteredOptions"
              :key="option[optionValueKey]"
              :class="optionHighlight(index, option)"
              class="options-option"
              @click="selectOption(option)"
              @mouseenter.self="pointerSet(index)">
              <slot
                name="label"
                :option="option">
                {{ option[optionLabelKey] }}
              </slot>
            </div>
          </div>
          <div class="shaded selected-items">
            <transition-group name="fade-move">
              <div
                v-for="s in selected"
                :key="s[optionValueKey]"
                class="selected-item-row">
                <slot
                  name="selected"
                  :entry="s">
                  <CircleFilled />
                  <span>{{ s[optionLabelKey] }}</span>
                </slot>
                <ButtonSmall
                  @click.native.stop="selectOption(s)">
                  {{ $t('remove') }}
                </ButtonSmall>
              </div>
            </transition-group>
          </div>
        </div>
        <div
          v-else>
          <div
            v-if="similarEntries.length"
            class="similar-box">
            <div class="similar-header">
              <i class="fa fa-exclamation-circle text-danger" />
              {{ $t('found-similar-objects') }}
            </div>
            <li
              v-for="s in similarEntries"
              :key="s[optionValueKey]"
              class="pos-relative">
              <span class="arrow">
                &rarr;
              </span>
              {{ s[optionLabelKey] }}
              <ButtonSmall
                @click.native.stop="selectSimilar(s)">
                {{ $t('select') }}
              </ButtonSmall>
            </li>
          </div>

          <slot
            name="create"
            :checkDupe="checkDupe"
            :selectOption="selectCreatedOption"></slot>
        </div>
      </KModal>
      <div
        class="selected-items">
        <div
          v-for="s in selected"
          :key="s[optionValueKey]"
          class="selected-item-row">
          <slot
            name="selected"
            :entry="s">
            <CircleFilled />
            <span>{{ s[optionLabelKey] }}</span>
          </slot>
        </div>
      </div>
      <div
        class="multiselect">
        <span>{{ selected.length }} {{ $t('selected') }}</span>
        <button
          class="button-edit"
          @click.self.prevent.stop="toggleFromButton">
          {{ open ? $t('close') : $t('edit') }}
        </button>
      </div>
    </template>
  </KFieldBase>
</template>

<script>

export default {
  props: {
    options: {
      type: Array,
      default: () => []
    },

    createEntry: {
      type: String,
      default: null
    },

    // should only deal with arrays of IDs, not objects
    idsOnly: {
      type: Boolean,
      default: false
    },

    disabled: {
      type: Boolean,
      default: false
    },

    multiple: {
      type: Boolean,
      default: true
    },

    helpText: {
      type: String,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: true
    },

    placeholder: {
      type: String,
      required: false,
      default: null
    },

    name: {
      type: String,
      required: true
    },

    value: {
      type: [Array],
      default: () => []
    },

    optionValueKey: {
      type: String,
      default: 'id'
    },

    optionLabelKey: {
      type: String,
      default: 'name'
    },

    optionsLimit: {
      type: Number,
      default: 99999
    },

    optionHeight: {
      type: Number,
      default: 37
    },

    maxHeight: {
      type: Number,
      default: 500
    }
  },

  data () {
    return {
      open: false,
      displayValue: '',
      searchString: '',
      preferredOpenDirection: 'below',
      optimizedHeight: this.maxHeight,
      pointer: 0,
      pointerDirty: false,
      showPointer: true,
      showCreateEntry: false,
      selected: [],
      similarEntries: []
    }
  },

  computed: {
    innerValue () {
      if (this.idsOnly) {
        return this.selected.map(v => v[this.optionValueKey])
      }
      return this.selected
    },

    pointerPosition () {
      return this.pointer * this.optionHeight
    },

    visibleElements () {
      return this.optimizedHeight / this.optionHeight
    },

    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    filteredOptions () {
      const search = this.searchString || ''
      const normalizedSearch = search.toLowerCase().trim()

      let options = this.options.concat()

      /* istanbul ignore else */
      options = this.filterOptions(options, normalizedSearch)

      return options.slice(0, this.optionsLimit)
    }
  },

  watch: {
    value (newVal, oldVal) {
      if (newVal !== oldVal) {
        this.initialize()
      }
    },

    options (newVal, oldVal) {
      if (!oldVal.length && newVal.length) {
        // options have been initialized
        this.initialize()
      } else {
        // options changed -- recheck selected
        this.selectFromValue()
      }
    }
  },

  created () {
    this.initialize()
  },

  methods: {
    initialize () {
      this.selectFromValue()
      this.displayData()
    },

    selectFromValue () {
      if (this.idsOnly) {
        this.selected = this.value
          .map(v => {
            if (typeof v === 'object') {
              return v
            } else {
              return this.options
                .find(o => o[this.optionValueKey].toString() === v.toString())
            }
          })
          .filter(o => o !== undefined)
      } else {
        this.selected = this.value
      }
    },

    emitSelected () {
      this.$emit('input', this.innerValue)
    },

    selectSimilar (option) {
      this.selectOption(option)
      this.toggleCreateEntry()
    },

    selectCreatedOption (option) {
      this.selectOption(option)
      this.toggleCreateEntry()
    },

    checkDupe (name) {
      if (name.length) {
        this.notValid = false
      }

      this.similarEntries = []

      this.options.forEach(option => {
        const jd = this.$utils.jaroDistance(option[this.optionLabelKey], name)
        if (jd > 0.95) {
          this.similarEntries.push(option)
        }
      })
    },

    toggleCreateEntry () {
      this.showCreateEntry = !this.showCreateEntry
    },

    includes (str, query) {
      if (str === undefined) str = 'undefined'
      if (str === null) str = 'null'
      if (str === false) str = 'false'
      const text = str.toString().toLowerCase()
      return text.indexOf(query.trim()) !== -1
    },

    filterOptions (options, search) {
      return options.filter(option => this.includes(option[this.optionLabelKey], search))
    },

    toggleFromButton () {
      this.toggle()
    },

    toggle () {
      this.showCreateEntry = false
      if (!this.open) {
        this.adjustPosition()
        this.open = true
        // this.searchString = this.displayValue
        this.$nextTick(() => this.$refs.search && this.$refs.search.focus())
      } else {
        this.$refs.modal.close().then(() => {
          this.open = false
        })
      }
    },

    displayData () {
      if (!this.innerValue || !this.innerValue.length) {
        this.displayValue = ''
      } else {
        const lblData = this.options.find(option => option[this.optionValueKey] === this.innerValue)
        if (lblData) {
          this.displayValue = lblData[this.optionLabelKey]
        }
      }
    },

    selectOption (option) {
      if (this.isSelected(option)) {
        this.selected = this.selected.filter(s => s !== option)
      } else {
        if (!this.multiple) {
          if (this.selected.length) {
            this.$alerts.alertError('OBS', this.$t('max-one'))
            return
          }
        }
        this.$set(this, 'selected', [option, ...this.selected])
      }
      this.searchString = ''
      this.emitSelected()
    },

    searchEnter () {
      if (this.filteredOptions.length) {
        if (this.filteredOptions.length === 1) {
          this.selectOption(this.filteredOptions[0])
        } else {
          this.selectOption(this.filteredOptions[this.pointer])
        }
      }
    },

    pointerForward () {
      /* istanbul ignore else */
      if (this.pointer < this.filteredOptions.length - 1) {
        this.pointer++
        /* istanbul ignore next */
        if (this.$refs.list.scrollTop <= this.pointerPosition - (this.visibleElements - 1) * this.optionHeight) {
          this.$refs.list.scrollTop = this.pointerPosition - (this.visibleElements - 1) * this.optionHeight
        }
      }
      this.pointerDirty = true
    },

    pointerBackward () {
      if (this.pointer > 0) {
        this.pointer--
        if (this.$refs.list.scrollTop >= this.pointerPosition) {
          this.$refs.list.scrollTop = this.pointerPosition
        }
      }

      this.pointerDirty = true
    },

    pointerReset () {
      this.pointer = 0
      if (this.$refs.list) {
        this.$refs.list.scrollTop = 0
      }
    },

    pointerAdjust () {
      if (this.pointer >= this.filteredOptions.length - 1) {
        this.pointer = this.filteredOptions.length
          ? this.filteredOptions.length - 1
          : 0
      }

      if (this.filteredOptions.length > 0) {
        this.pointerForward()
      }
    },

    pointerSet (index) {
      this.pointer = index
      this.pointerDirty = true
    },

    optionHighlight (index, option) {
      return {
        'option-highlight': index === this.pointer && this.showPointer,
        'option-selected': this.isSelected(option)
      }
    },

    isSelected (option) {
      return this.selected.find(s => s[this.optionValueKey].toString() === option[this.optionValueKey].toString())
    },

    adjustPosition () {
      this.optimizedHeight = 400
    }
  }
}
</script>

<style lang="postcss" scoped>
  .multiselect {
    @fontsize base/1;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-left: 15px;
    padding-right: 15px;
    height: 50px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;
  }

  .button-edit {
    @fontsize sm/1;
    border: 1px solid theme(colors.dark);
    padding: 8px 12px 10px;
    transition: all 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.input);
    }
  }

  .selected-items {
    .selected-item-row {
      align-items: center;
      line-height: 1;
      display: flex;
      padding-bottom: 9px;
    }
  }

  .options {
    overflow-y: auto;
    .options-option {
      cursor: pointer;
      color: theme(colors.dark);
      background-color: theme(colors.peach);

      user-select: none;
      padding: 8px 15px 4px;

      &.option-selected {
        background-color: theme(colors.blue);
        color: theme(colors.peach);
      }

      &.option-highlight {
        background-color: theme(colors.blue);
        color: theme(colors.peach);
      }

      &:hover {
        color: theme(colors.peach);
        background-color: theme(colors.dark);
      }
    }
  }

  .selected-items {
    display: flex;
    flex-direction: column;
    align-items: space-between;
    .selected-item-row {
      padding-bottom: 15px;
    }
  }

  .search {
    @fontsize base/1;
    width: 100%;
    border: 0;
    outline: none;
    background-color: theme(colors.input);
    margin-bottom: 10px;
    padding: 8px 15px 4px;
  }

  .similar-box {
    background-color: #ffff7e;
    margin-left: -10px;
    margin-right: -10px;
    padding-left: 10px;
    padding-right: 10px;
    padding-top: 10px;
    padding-bottom: 10px;

    .similar-header {
      margin-bottom: 15px;
      font-weight: 500;

      svg {
        margin-right: 15px;
      }
    }

    li {
      list-style-type: none;
      padding-top: 8px;
      padding-bottom: 8px;

      .arrow {
        margin-right: 15px;
      }
    }
  }
</style>
<i18n>
  {
    "en": {
      "back-to-list": "Back to list",
      "search": "Search...",
      "remove": "Remove",
      "found-similar-objects": "Found similar objects",
      "select": "Select",
      "selected": "selected",
      "close": "Close",
      "edit": "Edit",
      "max-one": "The field is configured for a max of 1 selection"
    },
    "no": {
      "back-to-list": "Tilbake til listen",
      "search": "Søk...",
      "remove": "Fjern",
      "found-similar-objects": "Fant lignende objekter",
      "select": "Velg",
      "selected": "valgte",
      "close": "Lukk",
      "edit": "Endre",
      "max-one": "Feltet er konfigurert til kun å ha én valgt verdi."
    }
  }
</i18n>
