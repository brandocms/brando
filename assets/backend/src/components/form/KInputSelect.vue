<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :compact="compact"
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
        ref="modalList"
        v-shortkey="['esc']"
        :ok-text="$t('close')"
        @shortkey.native="toggle"
        @ok="toggle()">
        <template #header>
          {{ showCreateEntry ? createEntry : label }}
          <div>
            <ButtonTiny
              v-if="createEntry"
              @click="toggleCreateEntry">
              <template v-if="!showCreateEntry">
                + {{ createEntry }}
              </template>
              <template v-else>
                {{ $t('back-to-list') }}
              </template>
            </ButtonTiny>

            <ButtonTiny @click="nullValue">
              {{ $t('reset') }}
            </ButtonTiny>
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
            <transition-group name="fadefast">
              <div
                v-for="(option, index) in filteredOptions"
                :key="option[optionValueKey] ? option[optionValueKey] : 'null'"
                ref="list"
                :class="optionHighlight(index, option)"
                class="options-option"
                @click="selectOption(option)">
                <slot
                  name="label"
                  :option="option">
                  {{ option[optionLabelKey] }}
                </slot>
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
        class="multiselect">
        <div>
          <slot
            name="selected"
            :entry="selected">
            <span>{{ selected ? selected[optionLabelKey] : $t('empty-selection') }}</span>
          </slot>
        </div>
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
import { gsap } from 'gsap'
import { ScrollToPlugin } from 'gsap/ScrollToPlugin'

gsap.registerPlugin(ScrollToPlugin)

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

    compact: {
      type: Boolean,
      default: false
    },

    disabled: {
      type: Boolean,
      default: false
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
      required: false,
      default: null
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
      type: [Object, String, Number],
      default: () => {}
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
      object: false,
      innerValue: null,
      open: false,
      displayValue: '',
      searchString: '',
      preferredOpenDirection: 'below',
      optimizedHeight: this.maxHeight,
      pointer: -1,
      pointerDirty: false,
      showPointer: true,
      showCreateEntry: false,
      selected: [],
      similarEntries: []
    }
  },

  computed: {
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
    selected (val) {
      if (!val) {
        return null
      }

      if (this.object) {
        this.innerValue = val
      } else {
        if (typeof val === 'object') {
          this.innerValue = val[this.optionValueKey]
        } else {
          this.innerValue = val
        }
      }

      this.$emit('input', this.innerValue)
    },

    options (newVal, oldVal) {
      if (!oldVal.length && newVal.length) {
        // options has been initialized
        this.initialize()
      }
    },

    value (newVal, oldVal) {
      if (newVal !== oldVal) {
        this.initialize()
      }
    }
  },

  created () {
    this.initialize()
  },

  methods: {
    initialize () {
      if (!this.value) {
        this.selected = null
        return
      }
      if (typeof this.value === 'object') {
        this.object = true
        this.selected = this.options.find(o => o[this.optionValueKey].toString() === this.value[this.optionValueKey].toString())
      } else {
        this.object = false
        this.selected = this.options.find(o => {
          if (!o[this.optionValueKey]) {
            return false
          }
          return o[this.optionValueKey].toString() === this.value.toString()
        })
      }

      this.displayData()
    },

    nullValue () {
      this.selected = null
      this.innerValue = null
      this.$emit('input', null)
      this.toggle()
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
        this.$nextTick(() => {
          this.$refs.search && this.$refs.search.focus()
          this.scrollToSelected()
        })
      } else {
        this.$refs.modalList.close().then(() => {
          this.open = false
        })
      }
    },

    scrollToSelected () {
      if (!this.selected) {
        return
      }

      gsap.to(this.$refs.list, { duration: 0.4, scrollTo: this.selectedIndex() * 43 })
    },

    selectedIndex () {
      return this.options.indexOf(this.selected)
    },

    displayData () {
      if (!this.innerValue) {
        this.displayValue = ''
      } else {
        const lblData = this.options.find(option => option[this.optionValueKey] === this.innerValue)
        if (lblData) {
          this.displayValue = lblData[this.optionLabelKey]
        }
      }
    },

    selectOption (option) {
      this.selected = option
      this.pointerSet(this.options.indexOf(option))
      this.toggle()
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
      if (!this.innerValue) {
        return false
      }

      if (this.object) {
        return this.selected === option
      } else {
        if (option[this.optionValueKey] === null) {
          return option[this.optionValueKey] === this.innerValue
        }
        return option[this.optionValueKey].toString() === this.innerValue.toString()
      }
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
      padding: 8px 15px 8px;

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

    .selected-items {
      display: flex;
      flex-direction: column;
      align-items: space-between;
      .selected-item-row {
        padding-bottom: 15px;
      }
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
      "empty-selection": "No selection",
      "close": "Close",
      "edit": "Edit",
      "reset": "Reset",
      "back-to-list": "Return to list",
      "search": "Search...",
      "found-similar-objects": "Found similar objects",
      "select": "Select"
    },
    "no": {
      "empty-selection": "Ingen valgt",
      "close": "Lukk",
      "edit": "Endre",
      "reset": "Nullstill",
      "back-to-list": "Tilbake til listen",
      "search": "Søk...",
      "found-similar-objects": "Fant lignende objekter",
      "select": "Velg"
    }
  }
</i18n>
