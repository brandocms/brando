<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :helpText="helpText"
    :value="value">
    <template v-slot>
      <input
        ref="input"
        :id="id"
        v-model="innerValue"
        :placeholder="placeholder"
        :name="name"
        :disabled="disabled"
        type="hidden">
    </template>
    <template v-slot:outsideValidator>
      <div
        class="megaselect__display">
        <div
          v-show="!open"
          class="megaselect__display__value"
          style="margin-top: 4px">
          {{ displayValue || "Ingen verdi" }}
        </div>
        <div
          v-show="open"
          class="megaselect__search"
          style="line-height: 1.5">
          <input
            ref="search"
            name="search"
            v-model="searchString"
            placeholder="Søk..."
            autocomplete="off"
            spellcheck="false"
            class="search"
            type="text"
            @keydown.enter.prevent="searchEnter"
            @keydown.down.prevent="pointerForward()"
            @keydown.up.prevent="pointerBackward()"
            @focus="$event.target.select()">

        </div>
        <button
          class="button-edit"
          @click.self.prevent.stop="toggleFromButton">
          {{ open ? 'Lukk' : 'Endre' }}
        </button>
      </div>

      <div
        v-if="open"
        ref="list"
        :style="{
          maxHeight: optimizedHeight + 'px',
          backgroundColor: '#ffe799',
          overflowY: 'auto'
        }"
        class="megaselect__options__wrapper b-1">
        <div
          v-for="(option, index) in filteredOptions"
          :key="option[optionValueKey]"
          :class="optionHighlight(index, option)"
          style="padding: 0.5rem 0.75rem"
          class="megaselect__options__option"
          @click="selectOption(option)"
          @mouseenter.self="pointerSet(index)">
          {{ option[optionLabelKey] }}
        </div>
      </div>
    </template>
  </KFieldBase>
</template>

<script>
export default {
  props: {
    hasError: {
      type: Boolean,
      default: false
    },

    options: {
      type: Array,
      default: () => []
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
      type: String
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
      type: [String, Number],
      default: ''
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
      showPointer: true
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
    },

    innerValue: {
      get () { return this.value },
      set (innerValue) { this.$emit('input', innerValue) }
    }
  },

  created () {
    this.innerValue = this.value
    // look up the value
    this.displayData()
  },

  methods: {
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
      if (!this.open) {
        this.adjustPosition()
        this.open = true
        // this.searchString = this.displayValue
        this.$nextTick(() => this.$refs.search && this.$refs.search.focus())
      } else {
        this.open = false
      }
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
      this.displayValue = option[this.optionLabelKey]
      this.searchString = ''
      this.toggle()
      this.innerValue = option[this.optionValueKey]
    },

    searchEnter () {
      if (this.filteredOptions.length) {
        if (this.filteredOptions.length === 1) {
          this.selectOption(this.filteredOptions[0])
        } else {
          this.displayValue = this.filteredOptions[this.pointer][this.optionLabelKey]
          // this.searchString = ''
          this.toggle()
          this.innerValue = this.filteredOptions[this.pointer][this.optionValueKey]
          // this.selectOption(this.filteredOptions[this.pointer])
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
        'megaselect__option--highlight': index === this.pointer && this.showPointer,
        'megaselect__option--selected': this.isSelected(option)
      }
    },

    isSelected (option) {
      return this.innerValue === option[this.optionValueKey]
    },

    adjustPosition () {
      if (typeof window === 'undefined') return

      const spaceAbove = this.$el.getBoundingClientRect().top
      const spaceBelow = window.innerHeight - this.$el.getBoundingClientRect().bottom
      const hasEnoughSpaceBelow = spaceBelow > this.maxHeight

      if (hasEnoughSpaceBelow || spaceBelow > spaceAbove || this.openDirection === 'below' || this.openDirection === 'bottom') {
        this.preferredOpenDirection = 'below'
        this.optimizedHeight = Math.min(spaceBelow - 40, this.maxHeight)
      } else {
        this.preferredOpenDirection = 'above'
        this.optimizedHeight = Math.min(spaceAbove - 40, this.maxHeight)
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  .megaselect__display {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-left: 15px;
    padding-right: 15px;
    height: 49px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;
  }

  .button-edit {
    @fontsize sm/1;
    border: 1px solid theme(colors.dark);
    padding: 8px 12px 3px;
    transition: all 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.input);
    }
  }

  .megaselect__option--selected,
  .megaselect__option--highlight {
    background-color: pink;
  }

  .search {
    padding: 0;
    border: 0;
    margin: 0;
    outline: none;
    background-color: transparent;
  }
</style>
