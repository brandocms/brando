<template>
  <div
    class="list"
    :data-level="level">
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
        store: {
          get: getOrder,
          set: storeOrder
        }
      }"
      tag="div"
      :data-sort-src="sortParent"
      class="sort-container">
      <div
        v-for="entry in entries"
        :key="entry[entryKey]"
        :data-id="entry[entryKey]"
        class="list-row">
        <div class="main-content">
          <template v-if="sortable">
            <div class="col-1">
              <SequenceHandle
                :class="sequenceHandle" />
            </div>
          </template>
          <slot name="row" v-bind:entry="entry"></slot>
        </div>
        <div class="children">
          <slot name="children" v-bind:entry="entry"></slot>
        </div>
      </div>
    </transition-group>
  </div>
</template>

<script>
// import { gsap } from 'gsap'

export default {
  props: {
    entries: {
      type: Array,
      required: true
    },

    sortable: {
      type: Boolean,
      default: false
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

    sequenceHandle: {
      type: String,
      default: 'sequence-handle'
    }
  },

  methods: {
    onAdd (e) {
      const moveEvent = {
        fromParentId: parseInt(e.from.dataset.sortSrc),
        toParentId: parseInt(e.to.dataset.sortSrc),
        id: parseInt(e.item.dataset.id)
      }

      this.$emit('move', moveEvent)
    },

    enter () {
      // const rows = this.$el.querySelectorAll('.list-row')
      // gsap.to(rows, { duration: 0.5, autoAlpha: 1, x: 0, stagger: 0.05 })
    },

    getOrder () {
      return this.entries
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray().map(Number)
      console.log(this.sortedArray)
      this.$emit('sort', this.sortedArray)
    },

    test () {
      console.log('DOES IT WORK?')
    }
  }
}
</script>

<style lang="postcss">
  .list {
    &[data-level="1"] {
      @space margin-top md;
    }

    &[data-level="2"] {
      .list-row {
        background-color: theme(colors.peach);
      }
    }

    a.link {
      border-bottom: none;
      position: relative;
      color: theme(colors.dark);

      &:after {
        border-top: 2px solid theme(colors.blue);
        content: '';
        position: absolute;
        right: 0;
        left: 0;
        bottom: 0;
        transition: right 350ms ease, color 550ms ease;
      }

      &:hover {
        &:after {
          right: 100%;
          color: theme(colors.blue)
        }
      }
    }

    a {
      border-bottom: none;
      position: relative;
      color: theme(colors.dark);

      &:after {
        border-top: 2px solid theme(colors.blue);
        content: '';
        position: absolute;
        right: 100%;
        bottom: 0;
        transition: right 350ms ease, color 550ms ease;
      }

      &:hover {
        &:after {
          transition: right 350ms ease, color 550ms ease;
          right: 0;
          left: 0;
          color: theme(colors.blue)
        }
      }
    }

    .list-header {
      @row;
      font-weight: 500;
      border-bottom: 1px solid rgba(0, 0, 0, 0.2);
    }

    .list-row {
      border-bottom: 1px solid rgba(0, 0, 0, 0.2);
      background-color: theme(colors.peachLighter);

      .main-content {
        @row;
        @space padding-top xs;
        @space padding-bottom xs;
        align-items: center;
        min-height: 50px;
      }
    }
  }
</style>
