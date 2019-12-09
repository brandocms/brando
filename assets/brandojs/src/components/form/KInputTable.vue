<template>
  <div class="input-table">
    <div class="label-wrapper">
      <label
        :for="id"
        class="control-label">
        <span>{{ label }}</span>
      </label>
    </div>

    <table>
      <slot name="head"></slot>
      <tr
        v-for="(entry, idx) in innerValue"
        :key="idx">
        <slot name="row" v-bind:entry="entry"></slot>
        <td class="action">
          <button
            type="button"
            class="delete"
            @click.self.stop.prevent="del(entry)">
            Slett
          </button>
        </td>
      </tr>
      <tr class="input-row" ref="newRow">
        <slot name="new" v-bind:newEntry="newEntry"></slot>
        <td class="action">
          <button
            type="button"
            class="add"
            @click.stop.prevent="add(newEntry)">
            OK
          </button>
        </td>
      </tr>
    </table>

    <div class="meta" v-if="helpText">
      <div
        v-if="helpText"
        class="help-text">
        —<span v-html="helpText" />
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

    value: {
      type: [Array],
      default: () => []
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
      newEntry: {}
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    innerValue: {
      get () { return this.value },
      set (innerValue) { this.$emit('input', innerValue) }
    }
  },

  created () {
    this.innerValue = this.value
  },

  methods: {
    add () {
      this.innerValue.push({ ...this.newEntry })
      this.newEntry = {}
      this.$refs.newRow.querySelector('input').focus()
    },

    del (entry) {
      const e = this.innerValue.find(e => e.id === entry.id)
      const idx = this.innerValue.indexOf(e)
      this.innerValue = [
        ...this.innerValue.slice(0, idx),
        ...this.innerValue.slice(idx + 1)
      ]
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
      font-weight: 500;
    }
  }

  table {
    width: 100%;

    tr {
      td {
        padding: 12px 0;
        border-bottom: 1px solid theme(colors.dark);

        &.action {
          width: 75px;
          text-align: right;
        }
      }

      th {
        @fontsize sm;
        font-weight: 500;
        text-align: left;
        border-bottom: 1px solid theme(colors.dark);
      }

      &.input-row {
        td {
          padding-right: 15px;

          &:last-of-type {
            padding-right: 0;
          }
        }
      }
    }

    input {
      @fontsize base/1;
      background-color: theme(colors.input);
      border: none;
      width: 100%;
      padding: 6px 10px 2px;
    }

    button {
      width: 75px;
      &.delete, &.add {
        @fontsize sm/1;
        border: 1px solid theme(colors.dark);
        padding: 6px 12px 2px;
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
</style>
