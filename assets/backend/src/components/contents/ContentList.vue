<template>
  <div
    v-if="actualEntries"
    class="list"
    :data-level="level">
    <div
      v-if="tools"
      class="list-tools">
      <div
        v-if="shouldStatus"
        class="status">
        <StatusLine
          v-if="$parent.queryVars"
          :all="true"
          :deleted="isSoftDeletable"
          :val="$parent.queryVars.status"
          @statusUpdate="changeStatus" />
      </div>
      <div
        v-if="shouldFilter"
        class="filters">
        <template v-if="objectFilters">
          <div
            v-for="f in filterKeys"
            :key="f.key"
            class="filter">
            <div
              class="filter-key"
              @click="changeFilterKey(f.key)">
              {{ f.label }}
            </div>
            <input
              v-model="filters[f.key]"
              :placeholder="$t('search')"
              type="text"
              @input="filterInput()" />
          </div>
        </template>
        <template v-else>
          <div
            v-for="(v, k) in filters"
            :key="k"
            class="filter">
            <div
              class="filter-key"
              @click="changeFilterKey(k)">
              {{ k }}
            </div>
            <input
              v-model="filters[k]"
              :placeholder="$t('search')"
              type="text"
              @input="filterInput()" />
          </div>
        </template>
      </div>

      <div
        v-if="false"
        class="order">
        <FontAwesomeIcon icon="sort-alpha-down" />
      </div>
      <transition
        v-if="selectable"
        name="fade">
        <div
          v-if="selectedRows.length"
          class="selected">
          {{ $t('with') }}
          <div class="circle">
            <span>{{ selectedRows.length }}</span>
          </div> {{ $t('selected-perform') }} &rarr;
          <CircleDropdown :inverted="true">
            <slot
              name="selected"
              :clearSelection="clearSelection"
              :entries="selectedRows">
            </slot>
          </CircleDropdown>
        </div>
      </transition>
    </div>
    <div class="list-header">
      <slot name="header"></slot>
    </div>
    <transition-group
      v-sortable="{
        group: level,
        dragoverBubble: true,
        disabled: !sortable,
        handle: '.' + sequenceHandle,
        animation: 250,
        easing: 'cubic-bezier(1, 0, 0, 1)',
        onAdd: onAdd,
        onStart: onSortStart,
        onEnd: onSortEnd,
        store: {
          get: getOrder,
          set: storeOrder
        }
      }"
      appear
      tag="div"
      :css="false"
      :data-sort-src="sortParent"
      class="sort-container">
      <div
        v-for="(entry, idx) in actualEntries"
        :key="entry[entryKey]"
        data-testid="contentlist-row"
        :data-testidx="idx"
        :data-test-level="level"
        :data-id="entry[entryKey]"
        :class="{ ...rowClasses(entry), selected: isSelected(entry[entryKey]), deleted: entry['deletedAt'] }"
        class="list-row">
        <div
          class="main-content"
          @mousedown="cacheSelected($event, entry[entryKey])"
          @mouseup="clearCachedRow()"
          @mouseover="selectIfMousePressed($event, entry[entryKey])"
          @click.stop="select(entry[entryKey])">
          <template v-if="sortable">
            <div class="col-1">
              <SequenceHandle :class="sequenceHandle" />
            </div>
          </template>
          <template v-if="status">
            <div class="status">
              <div v-if="entry.deletedAt">
                <FontAwesomeIcon
                  icon="trash-alt"
                  size="xs"
                  fixed-width />
              </div>
              <Status
                v-else
                :center="true"
                :entry="entry" />
            </div>
          </template>
          <slot
            name="row"
            :entry="entry"></slot>
        </div>
        <div class="children">
          <slot
            name="children"
            :entry="entry"
            :children="childProperty ? entry[childProperty]: []"></slot>
        </div>
      </div>
    </transition-group>
    <div
      v-if="paginationMeta"
      class="pagination">
      <div class="pagination-entries">
        &rarr; {{ paginationMeta.totalEntries }} {{ $t('entries') }}
      </div>
      <button
        v-for="p in pages"
        :key="p.number"
        :class="{ active: p.active }"
        @click="changePage(p.number)">
        {{ p.number }}
      </button>
    </div>
    <div
      v-if="actualEntries.length === 0"
      class="contentlist-empty">
      <slot name="empty"></slot>
    </div>
  </div>
</template>

<script>

import debounce from 'lodash/debounce'

export default {
  props: {
    entries: {
      type: [Array, Object],
      required: true
    },

    filter: {
      type: Boolean,
      default: false
    },

    selectable: {
      type: Boolean,
      default: true
    },

    tools: {
      type: Boolean,
      default: true
    },

    /* If the entry has children, this is the prop they are under (items, children, events, etc) */
    childProperty: {
      type: String,
      default: null
    },

    /*
    Keys we can choose between for filtering
    */
    filterKeys: {
      type: Array,
      default: () => []
    },

    status: {
      type: Boolean,
      default: false
    },

    sortable: {
      type: Boolean,
      default: false
    },

    sortableIntegerIds: {
      type: Boolean,
      default: true
    },

    /* if the sorting gets dragged between lists */
    sortParent: {
      type: String,
      default: '0'
    },

    level: {
      type: Number,
      default: 1
    },

    entryKey: {
      type: String,
      default: 'id'
    },

    rowClasses: {
      type: Function,
      default: () => {}
    },

    sequenceHandle: {
      type: String,
      default: 'sequence-handle'
    }
  },

  data () {
    return {
      filters: {},
      originalFilters: {},
      selectedRows: [],
      trashActive: false,
      sorting: false,
      cachedRowForSelection: null,
      objectFilters: false
    }
  },

  computed: {
    isSoftDeletable () {
      if (this.actualEntries.length) {
        return 'deletedAt' in this.actualEntries[0]
      }
      return false
    },

    shouldFilter () {
      return this.$parent?.queryVars?.hasOwnProperty('filter')
    },

    shouldStatus () {
      return this.status
    },

    hasMoreListener () {
      return this.$listeners && this.$listeners.more
    },

    actualEntries () {
      if (Array.isArray(this.entries)) {
        return this.entries
      }
      return this.entries.entries
    },

    paginationMeta () {
      if (typeof this.entries === 'object') {
        return this.entries.paginationMeta
      }
      return null
    },

    pages () {
      if (this.paginationMeta) {
        const ps = []
        for (let i = 1; i <= this.paginationMeta.totalPages; i += 1) {
          ps.push({
            number: i,
            active: i === this.paginationMeta.currentPage
          })
        }
        this.checkPagination()
        return ps
      }
      return []
    }
  },

  created () {
    if (this.filterKeys.length) {
      if (typeof this.filterKeys[0] === 'object' && this.filterKeys[0] !== null) {
        this.objectFilters = true
        this.filters[this.filterKeys[0].key] = ''
      } else {
        this.filters[this.filterKeys[0]] = ''
      }
    }
  },

  methods: {
    checkPagination () {
      if (this.paginationMeta.currentPage > this.paginationMeta.totalPages) {
        const queryVars = { ...this.$parent.queryVars, offset: 0 }
        this.$emit('updateQuery', queryVars)
      }
    },

    changePage (pageNumber) {
      const queryVars = { ...this.$parent.queryVars, offset: this.$parent.queryVars.limit * (pageNumber - 1) }
      this.$emit('updateQuery', queryVars)
    },

    changeStatus (status) {
      const queryVars = { ...this.$parent.queryVars, status }
      this.$emit('updateQuery', queryVars)
    },

    changeFilterKey (key, val) {
      if (this.filterKeys.length <= 1) {
        return
      }

      const idx = this.filterKeys.findIndex(k => k === key)
      if (idx !== this.filterKeys.length - 1) {
        delete this.filters[key]
        this.filters = {
          ...this.filters,
          [this.filterKeys[idx + 1]]: val
        }
      } else {
        delete this.filters[key]
        this.filters = {
          ...this.filters,
          [this.filterKeys[0]]: val
        }
      }
    },

    filterInput: debounce(function () {
      // clear out empty keys
      const filters = { ...this.filters }
      Object.keys(filters).forEach(key => (filters[key] === '') && delete filters[key])
      const queryVars = { ...this.$parent.queryVars, filter: filters, offset: 0 }
      this.$emit('updateQuery', queryVars)
    }, 750, true),

    clearSelection () {
      this.selectedRows = []
    },

    cacheSelected (e, id) {
      this.cachedRowForSelection = id
    },

    clearCachedRow () {
      this.cachedRowForSelection = null
    },

    select (id) {
      if (!this.selectable) {
        return
      }
      if (this.level > 1) {
        return
      }
      if (this.selectedRows.includes(id)) {
        this.selectedRows = this.selectedRows.filter(r => r !== id)
      } else {
        this.selectedRows.push(id)
      }
    },

    selectIfMousePressed (e, id) {
      if (this.sorting) {
        return
      }
      if ((e.buttons === 1 && e.shiftKey === true) && (e.fromElement.className === e.toElement.className)) {
        if (this.cachedRowForSelection) {
          this.selectedRows.push(this.cachedRowForSelection)
          this.clearCachedRow()
        }
        this.select(id)
      }
    },

    isSelected (id) {
      return this.selectedRows.includes(id)
    },

    onAdd (e) {
      const moveEvent = {
        fromParentId: parseInt(e.from.dataset.sortSrc),
        toParentId: parseInt(e.to.dataset.sortSrc),
        id: parseInt(e.item.dataset.id)
      }

      this.$emit('move', moveEvent)
    },

    onSortStart (e) {
      this.sorting = true
    },

    onSortEnd (e) {
      this.sorting = false
    },

    getOrder () {
      return this.actualEntries
    },

    storeOrder (sortable) {
      if (this.sortableIntegerIds) {
        this.sortedArray = sortable.toArray().map(Number)
      } else {
        this.sortedArray = sortable.toArray()
      }
      this.$emit('sort', this.sortedArray)
    }
  }
}
</script>

<style lang="postcss">
  .pagination {
    margin-top: 25px;
    max-width: 450px;

    .pagination-entries {
      font-size: 12px;
      margin-right: 15px;
      margin-bottom: 5px;
    }

    button {
      width: 30px;
      height: 30px;
      border: 1px solid theme(colors.dark);
      margin-right: 5px;
      margin-bottom: 5px;
      border-radius: 50%;
      font-size: 13px;
      transition: background-color 200ms ease;

      &.active {
        @color bg dark;
        @color fg peach;

        &:hover {
          @color bg dark;
        }
      }

      &:hover {
        @color bg peach;
      }
    }
  }

  .contentlist-empty {
    @fontsize h2;
    height: 25vh;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 600px;
  }

  .list-tools {
    @space margin-bottom xs;
    display: flex;
    min-height: 50px;

    .order, .trash {
      padding: 0 15px;
      min-height: 54px;
      height: 100%;
      display: flex;
      align-items: center;
      background-color: theme(colors.input);
      border-left: 5px solid #ffffff;
      transition: background-color 250ms ease;
    }

    .trash.trashSelected {
      background-color: theme(colors.peachDarker);
      transition: background-color 250ms ease;
    }

    .filters {
      width: 100%;
    }

    .filter {
      display: flex;
      align-items: center;
      background-color: theme(colors.input);
      height: 100%;

      input {
        @fontsize base;
        padding-top: 15px;
        padding-bottom: 12px;
        padding-left: 15px;
        padding-right: 15px;
        background-color: theme(colors.input);
        width: 100%;
        border: 0;
      }

      .filter-key {
        @font mono;
        cursor: pointer;
        user-select: none;
        left: 15px;
        font-size: 14px;
        text-transform: uppercase;
        border: 1px solid theme(colors.blue);
        padding: 2px 5px 0px;
        margin-top: 1px;
        margin-left: 15px;
        margin-right: 15px;
      }
    }

    .selected {
      @container;
      display: flex;
      align-items: center;
      justify-content: flex-end;
      margin-top: 25px;
      padding-right: 15px;
      padding-top: 25px;
      padding-bottom: 25px;
      position: fixed;
      bottom: 0;
      left: 0;
      width: 100%;
      z-index: 5;
      background-color: theme(colors.dark);
      color: theme(colors.peach);

      .circle {
        margin-left: 15px;
        margin-right: 15px;
        border: 1px solid theme(colors.peach);

        span {
          color: theme(colors.peach);
        }
      }

      .wrapper {
        margin-left: 25px;
      }
    }
  }

  .list {
    &[data-level="1"] {
      margin-top: 1rem;
    }

    &[data-level="2"] {
      margin-bottom: 10px;

      .list-row {
        background-color: #f3f3f3 !important;

        border-radius: 0px;

        &:first-of-type {
          border-radius: 20px 20px 0px 0px;
        }

        &:last-of-type {
          border-radius: 0px 0px 20px 20px;
        }
      }
      .list-tools {
        display: none;
      }
    }

    + .list {
      .list-header:empty {
        display: none;
      }
    }

    a.link, a.entry-link {
      border-bottom: none;
      position: relative;
      color: theme(colors.dark);
      text-decoration: underline;
      text-decoration-color: transparent;
      transition: text-decoration-color 1s ease;

      &:after {
        content: '↗';
        opacity: 0.4;
        right: 0;
        color: theme(colors.dark);
        transform: scale(0.8) translateY(2px) rotate(0deg);
        transition: transform 250ms ease, opacity 250ms ease, color 250ms ease;
        display: inline-block;
      }

      &:hover {
        text-decoration-color: theme(colors.blue);
        &:after {
          opacity: 1;
          transform: scale(0.8) translateY(2px) rotate(45deg);
        }
      }
    }

    a {
      border-bottom: none;
      position: relative;
      color: theme(colors.dark);
    }

    .list-header {
      @row;
      font-weight: 500;
      padding-bottom: 10px;
    }

    .list-row {
      background-color: white;
      user-select: none;
      border-radius: 20px;

      &:nth-of-type(even) {
        background-color: #fafafa;
      }

      .center {
        display: flex;
        justify-content: center;
        align-items: center;
      }

      &.selected {
        background-color: theme(colors.peachDarker);
        transition: background-color 250ms ease;
      }

      &.deleted {
        background-color: #e8e8e8;
        transition: background-color 250ms ease;
      }

      .main-content {
        @row;
        @space padding-top 10px;
        @space padding-bottom 10px;
        align-items: center;
        min-height: 50px;

        .status {
          position: absolute;
          margin-left: -36px;
        }
      }
    }
  }
</style>

<i18n>
{
  "en": {
    "search": "Search...",
    "with": "With",
    "selected-perform": "selected, do:",
    "more": "Load more, if available",
    "entries": "entries"
  },
  "no": {
    "search": "Søk...",
    "with": "Med",
    "selected-perform": "valgte utfør handling:",
    "more": "Last inn flere, hvis tilgjengelig",
    "entries": "objekter"
  }
}
</i18n>
