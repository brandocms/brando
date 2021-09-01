<template>
  <div class="field-wrapper">
    <div class="input-table">
      <div class="label-wrapper">
        <label
          :for="id"
          class="control-label">
          <span>{{ label }}</span>
        </label>
      </div>

      <div class="kinput-table-wrapper">
        <table
          class="kinput-table"
          :style="fixedLayout ? 'table-layout: fixed' : ''">
          <slot name="head"></slot>
          <transition-group
            v-sortable="{
              dragoverBubble: true,
              disabled: !sortable,
              handle: '.sequence-handle',
              animation: 250,
              easing: 'cubic-bezier(1, 0, 0, 1)',
              store: {
                get: getOrder,
                set: storeOrder
              }
            }"
            appear
            tag="tbody"
            :css="false"
            class="sort-container">
            <tr
              v-for="entry in innerValue"
              :key="entry[idKey]"
              :data-id="entry[idKey]">
              <td
                v-if="sortable"
                style="width: 50px; vertical-align: middle">
                <SequenceHandle class="sequence-handle" />
              </td>
              <slot
                v-if="entry !== editEntry"
                name="row"
                :entry="entry"></slot>
              <slot
                v-else-if="editRows"
                name="edit"
                :editEntry="newEditEntry"
                :callback="() => {editDone(entry)}"></slot>

              <td
                v-if="deleteRows || editRows"
                class="action fit">
                <div class="button-wrapper">
                  <CircleButton
                    v-if="entry !== editEntry && editRows"
                    class="edit"
                    @click.native.stop.prevent="edit(entry)">
                    <FontAwesomeIcon
                      icon="pencil-alt"
                      size="xs" />
                  </CircleButton>
                  <CircleButton
                    v-else-if="editRows"
                    class="edit"
                    @click.native.stop.prevent="editDone(entry)">
                    <FontAwesomeIcon
                      icon="check"
                      size="xs" />
                  </CircleButton>
                  <CircleButton
                    class="delete"
                    @click.native.stop.prevent="del(entry)">
                    <FontAwesomeIcon
                      icon="minus"
                      size="xs" />
                  </CircleButton>
                </div>
              </td>
            </tr>
            <tr
              v-if="addRows"
              ref="addRow"
              key="addrow"
              class="input-row">
              <td v-if="sortable" />
              <slot
                name="new"
                :newEntry="newEntry"></slot>
              <td class="action fit">
                <CircleButton
                  class="add"
                  @click.native.stop.prevent="add(newEntry)">
                  <FontAwesomeIcon
                    icon="plus"
                    size="xs" />
                </CircleButton>
              </td>
            </tr>
          </transition-group>
        </table>
      </div>

      <div
        v-if="helpText"
        class="meta">
        <div
          v-if="helpText"
          class="help-text">
          —<span v-html="helpText" />
        </div>
      </div>
    </div>
  </div>
</template>

<script>

export default {
  props: {
    name: {
      type: String,
      required: true
    },

    newEntryTemplate: {
      type: Object,
      default: () => {}
    },

    sortable: {
      type: Boolean,
      default: false
    },

    addRows: {
      type: Boolean,
      default: true
    },

    fixedLayout: {
      type: Boolean,
      default: true
    },

    /**
     * !TODO DEPRECATE THIS IN FAVOR OF `addRows`
     * */
    newRows: {
      type: Boolean
    },

    deleteRows: {
      type: Boolean,
      default: true
    },

    editRows: {
      type: Boolean,
      default: false
    },

    value: {
      type: [Array],
      default: () => []
    },

    idKey: {
      type: String,
      default: 'id'
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: true
    }
  },

  data () {
    return {
      editEntry: {},
      newEditEntry: {},
      newEntry: {}
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    innerValue: {
      get () {
        return this.value
      },
      set (innerValue) {
        this.$emit('input', innerValue)
      }
    }
  },

  created () {
    this.newEntry = this.$utils.clone(this.newEntryTemplate)
    this.innerValue = this.value
    if (this.newRows) {
      console.error('==> KInputTable: `newRows` has been deprecated, use `addRows` instead!')
    }
  },

  methods: {
    getOrder () {
      return this.innerValue
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray()

      const arr = this.innerValue.sort((a, b) => {
        return this.sortedArray.indexOf(a.id) - this.sortedArray.indexOf(b.id)
      })

      this.$set(this, 'innerValue', arr)
      this.$emit('sort', this.sortedArray)
    },

    add () {
      this.innerValue.push({ ...this.newEntry, id: this.$utils.guid() })
      this.newEntry = this.$utils.clone(this.newEntryTemplate)
      this.$refs.addRow.querySelector('input').focus()
    },

    edit (entry) {
      this.editEntry = entry
      this.newEditEntry = { ...entry }
    },

    editDone (entry) {
      const idx = this.innerValue.indexOf(entry)
      this.innerValue = [
        ...this.innerValue.slice(0, idx),
        this.newEditEntry,
        ...this.innerValue.slice(idx + 1)
      ]
      this.editEntry = {}
    },

    del (entry) {
      if (!entry[this.idKey]) {
        this.$delete(this.innerValue, this.innerValue.indexOf(entry))
        return
      }

      const e = this.innerValue.find(e => {
        return e[this.idKey] === entry[this.idKey]
      })
      const idx = this.innerValue.indexOf(e)
      this.$delete(this.innerValue, idx)
    }
  }
}
</script>

<style lang="postcss" scoped>
  .input-table {
    margin-bottom: 40px;
  }
  .label-wrapper {
    margin-bottom: 4px;

    label {
      @fontsize form.label;
      font-weight: 500;
    }
  }

  .kinput-table-wrapper {
    border: 1px solid theme(colors.dark);
    padding: 15px;
  }

  .kinput-table {
    width: 100%;

    tr {
      border-bottom: 1px solid theme(colors.dark);

      td {
        vertical-align: top;
        padding: 12px 0;
        padding-right: 15px;

        & >>> .field-wrapper {
          margin-bottom: 15px;
        }

        &:last-of-type {
          padding-right: 0;
        }

        &.action {
          width: 95px;
          text-align: right;
        }

        >>> &.align-right {
          text-align: right;
        }

        >>> &.monospace {
          @font mono base(0.75);
        }
      }

      th {
        @fontsize sm;
        font-weight: 500;
        text-align: left;
        border-bottom: 1px solid theme(colors.dark);

        >>> &.align-right {
          text-align: right;
        }
      }

      &.input-row {
        border-bottom: none;

        td {
          padding-right: 15px;

          &:last-of-type {
            padding-right: 0;
          }
        }

        >>> td {
          padding-top: 15px;
        }
      }
    }

    input {
      @fontsize sm/1;
      background-color: theme(colors.input);
      border: none;
      width: 100%;
      padding: 6px 10px 6px;
    }

    button {
      width: 75px;
      &.delete, &.add {
        @fontsize sm/1;
        border: 1px solid theme(colors.dark);
        padding: 6px 12px 6px;
        transition: all 0.25s ease;
      }
      &.delete {
        &:hover {
          background-color: red;
        }
      }

      &.add {
        &:hover {
          background-color: theme(colors.blue);
          color: theme(colors.peach);
        }
      }
    }
  }

  .button-wrapper {
    display: flex;

    button + button {
      margin-left: 5px;
    }
  }
</style>
