<template>
  <div
    :class="fullscreen ? 'villain-fullscreen': ''"
    class="villain-editor">
    <div class="villain-editor-backdrop" />
    <div
      v-if="showAutosaves"
      class="villain-editor-autosave-list-popup">
      {{ $t('autosaved-versions') }}
      <div
        v-for="(a, idx) in autosaveEntries"
        :key="idx"
        class="villain-editor-autosave-list-popup-item">
        <div class="villain-editor-autosave-list-popup-item-date">
          <i class="fa fa-fw fa-file mr-2" /> {{ format(a.timestamp, 'nb_NO') }}
        </div>
        <ButtonSmall
          @click.native.prevent="restoreAutosave(a)">
          {{ $t('restore-this-version') }}
        </ButtonSmall>
      </div>
    </div>
    <div class="villain-editor-toolbar">
      <div
        class="villain-editor-instructions">
        <template v-if="showPlus">
          {{ $t('click-plus-to-add-block') }}
        </template>
      </div>
      <div class="villain-editor-controls float-right">
        <div class="villain-editor-autosave-status">
          {{ autosaveStatus }}
        </div>
        <div
          v-popover="$t('show-autosaved-versions')"
          @click="toggleAutosaves">
          <IconAutosave />
        </div>
        <div
          v-popover="showSource ? $t('close-source-view') : $t('open-source-view')"
          @click="toggleSource()">
          <template v-if="showSource">
            <IconClose />
          </template>
          <template v-else>
            <IconSource />
          </template>
        </div>
        <div
          v-popover="fullscreen ? $t('close-fullscreen') : $t('open-fullscreen')"
          @click="toggleFullscreen()">
          <template v-if="fullscreen">
            <IconClose />
          </template>
          <template v-else>
            <IconFullscreen />
          </template>
        </div>
      </div>
    </div>
    <template
      v-if="showSource">
      <div class="villain-editor-source">
        <textarea
          ref="tasource"
          v-model="src" />
        <div class="d-flex justify-content-center">
          <button
            type="button"
            class="btn btn-primary mt-4"
            @click="updateSource">
            {{ $t('update') }}
          </button>
        </div>
      </div>
    </template>
    <template
      v-else>
      <BlockContainer
        v-model="innerValue"
        :ready="ready"
        @add="addBlock"
        @move="moveBlock"
        @delete="deleteBlock"
        @hide="hideBlock"
        @show="showBlock"
        @duplicate="duplicateBlock"
        @order="orderBlocks" />
    </template>
  </div>
</template>

<script>
import Vue from 'vue'
import autosize from 'autosize'
import cloneDeep from 'lodash/cloneDeep'
import { format, register } from 'timeago.js'
import nbNO from 'timeago.js/lib/lang/nb_NO'
import { VTooltip } from 'v-tooltip'
import shortid from 'shortid'

import standardComponents from './blocks/standard'
import systemComponents from './blocks/system'
import toolsComponents from './blocks/tools'
import IconAutosave from './icons/IconAutosave'
import IconClose from './icons/IconClose'
import IconFullscreen from './icons/IconFullscreen'
import IconSource from './icons/IconSource'
import STANDARD_BLOCKS from '../config/standardBlocks.js'
import { alerts } from '../../../utils/alerts'
import { addAutoSave, getAutoSaves } from '../utils/autoSave.js'
import getTimestamp from '../utils/getTimestamp.js'
import { AUTOSAVE_INTERVAL, AUTOSAVE_STATUS_TEXT_DURATION } from '../config/autoSave.js'
import { TweenMax } from 'gsap'

for (const key in standardComponents) {
  if (standardComponents.hasOwnProperty(key)) {
    Vue.component(key, standardComponents[key])
  }
}

for (const key in systemComponents) {
  if (systemComponents.hasOwnProperty(key)) {
    Vue.component(key, systemComponents[key])
  }
}

for (const key in toolsComponents) {
  if (toolsComponents.hasOwnProperty(key)) {
    Vue.component(key, toolsComponents[key])
  }
}

export default {
  name: 'VillainEditor',

  components: {
    IconAutosave,
    IconClose,
    IconFullscreen,
    IconSource
  },

  directives: { popover: VTooltip },

  inject: [
    'adminChannel'
  ],

  provide () {
    const state = {}
    const available = {}
    const headers = {}
    const urls = {}

    Object.defineProperty(state, 'showPlus', {
      enumerable: true,
      get: () => this.showPlus
    })

    Object.defineProperty(state, 'showModules', {
      enumerable: true,
      get: () => this.showModules
    })

    Object.defineProperty(available, 'blocks', {
      enumerable: true,
      get: () => this.availableBlocks
    })

    Object.defineProperty(available, 'allBlocks', {
      enumerable: true,
      get: () => this.allBlocks
    })

    Object.defineProperty(available, 'modules', {
      enumerable: true,
      get: () => this.availableModules
    })

    Object.defineProperty(available, 'entryData', {
      enumerable: true,
      get: () => this.entryData
    })

    Object.defineProperty(headers, 'extra', {
      enumerable: true,
      get: () => this.extraHeaders
    })

    /**
     * URLS
     */
    Object.defineProperty(urls, 'base', {
      enumerable: true,
      get: () => `${this.server}${this.baseURL}`
    })
    Object.defineProperty(urls, 'browse', {
      enumerable: true,
      get: () => `${this.server}${this.browseURL}`
    })

    return {
      vModuleMode: this.moduleMode,
      available,
      headers,
      urls,
      state,
      refresh: this.refresh
    }
  },

  props: {
    json: {
      type: [String, Array],
      default: '[]'
    },

    value: {
      type: [Array],
      default: () => []
    },

    entryData: {
      type: Object,
      default: () => {}
    },

    maxBlocks: {
      type: Number,
      default: 0
    },

    moduleMode: {
      type: Boolean,
      default: false
    },

    server: {
      type: String,
      default: ''
    },

    baseURL: {
      type: String,
      default: '/admin/api/villain/'
    },

    browseURL: {
      type: String,
      default: '/admin/api/villain/browse/'
    },

    modulesURL: {
      type: String,
      default: '/admin/api/villain/modules/'
    },

    moduleSequenceURL: {
      type: String,
      default: '/admin/api/villain/modules/sequence/'
    },

    imageSeries: {
      type: String,
      default: 'post'
    },

    extraHeaders: {
      type: Object,
      default: () => {}
    },

    extraBlocks: {
      type: Array,
      default: () => []
    },

    showModules: {
      type: Boolean,
      default: true
    },

    visibleBlocks: {
      type: Array,
      default: () => []
    },

    modules: {
      type: String,
      default: 'all'
    }
  },

  data () {
    return {
      autosaveEntries: [],
      autosaveStatus: '',
      blockCount: 0,
      blocks: [],
      lastAutosavedAt: null,
      lastValue: null,
      needsRefresh: false,
      showAutosaves: false,
      showSource: false,
      fullscreen: false,
      availableModules: [],
      ready: false,
      src: '[]'
    }
  },
  computed: {
    innerValue: {
      get () {
        return this.value
      },
      set (innerValue) {
        this.$emit('input', innerValue)
      }
    },

    showPlus () {
      if (this.maxBlocks === 0) {
        return true
      }
      if (this.maxBlocks > 0 && this.blockCount === this.maxBlocks) {
        return false
      }
      return true
    },

    allBlocks () {
      let allBlocks = STANDARD_BLOCKS[this.$i18n.locale]

      if (this.extraBlocks.length) {
        allBlocks = allBlocks + STANDARD_BLOCKS[this.$i18n.locale]
      }

      return allBlocks
    },

    availableBlocks () {
      let availableBlocks = STANDARD_BLOCKS[this.$i18n.locale]

      if (this.extraBlocks.length) {
        availableBlocks = availableBlocks + STANDARD_BLOCKS[this.$i18n.locale]
      }

      if (this.visibleBlocks.length) {
        // filter according to visibleBlocks
        availableBlocks = availableBlocks.filter(b => this.visibleBlocks.includes(b.component))
      }

      return availableBlocks
    }
  },

  async created () {
    if (this.modules) {
      this.availableModules = await this.fetchModules(this.modules)
    }

    // this.innerValue = this.addUIDs()

    // validate each block!
    for (let idx = 0; idx < this.innerValue.length; idx++) {
      const block = this.innerValue[idx]
      this.validateBlock(block)
    }

    // reconvert to start fresh if there are added props
    if (this.needsRefresh) {
      this.refresh(false)
      console.debug('==> Refreshed Villain Blocks due to missing props.')
    }

    register('nb_NO', nbNO)

    this.lastEdit = getTimestamp()

    // setup autosave interval
    setInterval(() => {
      // Only autosave if there are changes
      if (!this.lastValue) {
        this.lastValue = JSON.stringify(this.innerValue)
      }

      if (JSON.stringify(this.innerValue) !== this.lastValue) {
        this.autosaveStatus = this.$t('autosaving')
        setTimeout(() => {
          this.autosaveStatus = ''
        }, AUTOSAVE_STATUS_TEXT_DURATION)
        addAutoSave(this.innerValue)
        this.lastValue = JSON.stringify(this.innerValue)
      }
    }, AUTOSAVE_INTERVAL)

    this.ready = true
  },

  mounted () {
    this.animateIn()
  },

  methods: {
    async fetchModules (namespace = 'all') {
      return new Promise((resolve, reject) => {
        this.adminChannel.channel
          .push('villain:list_modules', { namespace })
          .receive('ok', payload => { resolve(payload.modules) })
      })

    },

    validateBlock (block) {
      const bpBlock = this.availableBlocks.find(b => b.component.toLowerCase() === block.type)
      if (!Object.prototype.hasOwnProperty.call(block, 'uid')) {
        this.$set(block, 'uid', this.createUID()) // or this.$utils.guid()?
      }

      if (bpBlock) {
        switch (block.type) {
          case 'datatable':
            if (Array.isArray(block.data)) {
              console.log('==> Converting datatable [] to new format {}')
              const rows = block.data
              this.$set(block, 'data', { rows })
              this.needsRefresh = true
              break
            }

            if (block.data.rows) {
              block.data.rows = block.data.rows.map(r => {
                if (!r.id) {
                  return { ...r, id: this.$utils.guid() }
                }
                return r
              })
            }

            break

          case 'timeline':
            if (Array.isArray(block.data)) {
              console.log('==> Converting timeline [] to new format {}')
              const rows = block.data
              this.$set(block, 'data', { rows })
              this.needsRefresh = true
            }
            break

          case 'datasource':
            if (block.data.type === 'many') {
              this.$alerts.alertError('OBS!', this.$t('old-datasource-type'))
              this.$set(block.data, 'type', 'list')
              this.needsRefresh = true
            }
            /**
             * Check for old format using `template`
             */
            if (block.data.wrapper) {
              this.$alerts.alertError('OBS!', this.$t('old-datasource-wrapper'))
              if (block.data.wrapper) {
                console.error('Datasource/Datakilde-wrapper\r\n\r\n', block.data.wrapper)
              }

              delete block.data.wrapper
            }

            if (block.data.template) {
              this.$set(block.data, 'module_id', block.data.template)
              delete block.data.template
            }

            break

          case 'container':
            if (block.data.blocks && block.data.blocks.length) {
              for (let idx = 0; idx < block.data.blocks.length; idx++) {
                const containedBlock = block.data.blocks[idx]
                this.validateBlock(containedBlock)
              }
            }
            break
        }

        const blueprint = bpBlock.dataTemplate
        for (const blueprintProp in blueprint) {
          if (!(blueprintProp in block.data)) {
            this.$set(block.data, blueprintProp, blueprint[blueprintProp])
            console.debug(`==> Added missing property '${blueprintProp}' to '${block.type}'`)
            this.needsRefresh = true
          }
        }
      } else {
        if (block.type === 'module') {
          if (!block.data.hasOwnProperty('multi')) {
            this.$set(block.data, 'multi', false)
          }
          if (block.data.refs && block.data.refs.length) {
            for (let idx = 0; idx < block.data.refs.length; idx++) {
              const refBlock = block.data.refs[idx].data
              this.validateBlock(refBlock)
            }
          }

          if (block.data.entries && block.data.entries.length) {
            for (let idx = 0; idx < block.data.entries.length; idx++) {
              const entry = block.data.entries[idx]

              if (!entry.hasOwnProperty('id')) {
                console.log('==> entry in ModuleBlock is lacking an `id`')
                this.$set(entry, 'id', shortid.generate())
              }

              for (let xdx = 0; xdx < entry.refs.length; xdx++) {
                const refBlock = entry.refs[xdx].data
                this.validateBlock(refBlock)
              }
            }
          }
        }
      }
    },

    format (time, locale) {
      return format(time, locale)
    },

    toggleAutosaves () {
      if (this.showAutosaves) {
        this.showAutosaves = false
        return
      }
      this.autosaveEntries = getAutoSaves()
      this.showAutosaves = true
    },

    restoreAutosave (a) {
      alerts.alertConfirm('OBS!', this.$t('replace-with-autosave'), data => {
        if (data) {
          this.innerValue = a.content
          this.showAutosaves = false
        }
      })
    },

    animateIn (speed = 1) {
      const instructions = this.$el.querySelector('.villain-editor-instructions')
      const controls = this.$el.querySelector('.villain-editor-controls')

      TweenMax.fromTo(this.$el, speed, { opacity: 0 }, { opacity: 1 })

      if (instructions) {
        TweenMax.fromTo(instructions, speed, { x: -5, opacity: 0 }, { x: 0, opacity: 1, delay: 0.9 })
      }
      if (controls) {
        TweenMax.fromTo(controls, speed, { x: -5, opacity: 0 }, { x: 0, opacity: 1, delay: 0.5 })
        TweenMax.staggerFromTo(this.$el.querySelectorAll('.villain-editor-controls > div'), speed, { x: -3, opacity: 0 }, { x: 0, opacity: 1, delay: 1.2 }, 0.1)
      }
    },

    async updateModules () {
      this.availableModules = await this.fetchModules(this.modules)
    },

    updateSource () {
      this.innerValue = JSON.parse(this.src)
      this.toggleSource()
    },

    toggleSource () {
      if (this.showSource) {
        this.showSource = false
      } else {
        this.src = JSON.stringify(this.innerValue, null, 2)
        this.showSource = true
        autosize(this.$refs.tasource)
      }
    },

    refresh (animate = true) {
      const bx = cloneDeep(this.innerValue)
      this.innerValue = bx

      if (animate) {
        this.animateIn(0.5)
      }
    },

    toggleFullscreen () {
      this.fullscreen = !this.fullscreen
    },

    addUIDs () {
      return [...this.innerValue].map(b => {
        if ('uid' in b) {
          return b
        } else {
          return { ...b, uid: this.createUID() }
        }
      })
    },

    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    },

    /*
    ** Strip out uid and locked properties
    **/
    stripMeta (obj) {
      if (!obj) {
        return obj
      }

      if (obj.hasOwnProperty('uid')) {
        delete obj.uid
      }

      if (obj.hasOwnProperty('locked')) {
        delete obj.locked
      }

      return obj
    },

    addBlock ({ block: blockTpl, after, parent }) {
      let block
      // a standard component blueprint
      if (blockTpl.hasOwnProperty('component')) {
        if (blockTpl.component === 'Columns') {
          block = {
            type: blockTpl.component.toLowerCase(),
            data: [...blockTpl.dataTemplate],
            uid: blockTpl.uid
          }
        } else {
          block = {
            type: blockTpl.component.toLowerCase(),
            data: { ...blockTpl.dataTemplate },
            uid: blockTpl.uid
          }
        }
      } else {
        // a module block
        block = cloneDeep(blockTpl)
      }

      // no after, no parent = + at the top OR first one if empty
      if (!after && !parent) {
        // if we have blocks, it's the top + so we add to top
        if (this.innerValue.length) {
          this.innerValue = [
            block,
            ...this.innerValue
          ]
        } else {
          this.innerValue = [
            ...this.innerValue,
            block
          ]
        }
        return
      }

      if (parent) {
        // child of a column OR container
        const mainBlock = this.innerValue.find(b => {
          if (b.type === 'columns') {
            for (const key of Object.keys(b.data)) {
              const x = b.data[key]
              if (x.uid === parent) {
                return x
              }
            }
          } else if (b.type === 'container') {
            if (b.uid === parent) {
              return b
            }
          }
        })

        let parentBlock = null
        if (mainBlock) {
          if (mainBlock.type === 'columns') {
            // we have the main block -- add to the correct parent
            for (const key of Object.keys(mainBlock.data)) {
              const y = mainBlock.data[key]
              if (y.uid === parent) {
                parentBlock = y
              }
            }

            if (after) {
              const p = parentBlock.data.find(b => b.uid === after)
              if (!p) {
                console.error('--- NO UID FOR "AFTER"-BLOCK')
              }
              const idx = parentBlock.data.indexOf(p)

              if (idx + 1 === parentBlock.data.length) {
                // index is last, just add to list
                parentBlock.data = [
                  ...parentBlock.data,
                  block
                ]
                return
              }

              // we're adding in the midst of things
              parentBlock.data = [
                ...parentBlock.data.slice(0, idx + 1),
                block,
                ...parentBlock.data.slice(idx + 1)
              ]
            } else {
              parentBlock.data = [
                block,
                ...parentBlock.data
              ]
            }
          } else {
            // container
            if (after) {
              const p = mainBlock.data.blocks.find(b => b.uid === after)
              if (!p) {
                console.error('--- NO UID FOR "AFTER"-BLOCK')
              }
              const idx = mainBlock.data.blocks.indexOf(p)

              if (idx + 1 === mainBlock.data.blocks.length) {
                // index is last, just add to list
                mainBlock.data.blocks = [
                  ...mainBlock.data.blocks,
                  block
                ]
                return
              }

              // we're adding in the midst of things
              mainBlock.data.blocks = [
                ...mainBlock.data.blocks.slice(0, idx + 1),
                block,
                ...mainBlock.data.blocks.slice(idx + 1)
              ]
            } else {
              mainBlock.data.blocks = [
                block,
                ...mainBlock.data.blocks
              ]
            }
          }
        }
        return
      }

      if (after) {
        const p = this.innerValue.find(b => b.uid === after)
        if (!p) {
          console.error('--- NO UID FOR "AFTER"-BLOCK')
        }
        const idx = this.innerValue.indexOf(p)

        if (idx + 1 === this.innerValue.length) {
          // index is last, just add to list
          this.innerValue = [
            ...this.innerValue,
            block
          ]
          return
        }

        // we're adding in the midst of things
        this.innerValue = [
          ...this.innerValue.slice(0, idx + 1),
          block,
          ...this.innerValue.slice(idx + 1)
        ]
      }
    },

    moveBlock ({ block, after, parent }) {
      this.deleteBlock(block)

      this.$nextTick(() => {
        if (!after && !parent) {
          // if we have blocks, it's the top + so we add to top
          if (this.innerValue.length) {
            this.innerValue = [
              block,
              ...this.innerValue
            ]
          } else {
            this.innerValue = [
              block
            ]
          }
        }

        /*
        ** Block is moved into a column OR container
        */
        if (parent) {
          // child of a column
          const mainBlock = this.innerValue.find(b => {
            if (b.type === 'columns') {
              for (const key of Object.keys(b.data)) {
                const x = b.data[key]
                if (x.uid === parent) {
                  return x
                }
              }
            } else if (b.type === 'container') {
              if (b.uid === parent) {
                return b
              }
            }
          })

          let parentBlock = null
          if (mainBlock) {
            if (mainBlock.type === 'columns') {
              // we have the main block -- add to the correct parent
              for (const key of Object.keys(mainBlock.data)) {
                const y = mainBlock.data[key]
                if (y.uid === parent) {
                  parentBlock = y
                }
              }

              if (after) {
                const p = parentBlock.data.find(b => b.uid === after)
                if (!p) {
                  console.error('--- NO UID FOR "AFTER"-BLOCK')
                }
                const idx = parentBlock.data.indexOf(p)

                if (idx + 1 === parentBlock.data.length) {
                  // index is last, just add to list
                  parentBlock.data = [
                    ...parentBlock.data,
                    block
                  ]
                  return
                }

                // we're adding in the midst of things
                parentBlock.data = [
                  ...parentBlock.data.slice(0, idx + 1),
                  block,
                  ...parentBlock.data.slice(idx + 1)
                ]
              } else {
                parentBlock.data = [
                  block,
                  ...parentBlock.data
                ]
              }
            } else if (mainBlock.type === 'container') {
              parentBlock = mainBlock

              if (after) {
                const p = parentBlock.data.blocks.find(b => b.uid === after)
                if (!p) {
                  console.error('--- NO UID FOR "AFTER"-BLOCK')
                }
                const idx = parentBlock.data.blocks.indexOf(p)

                if (idx + 1 === parentBlock.data.blocks.length) {
                  // index is last, just add to list
                  parentBlock.data.blocks = [
                    ...parentBlock.data.blocks,
                    block
                  ]
                  return
                }

                // we're adding in the midst of things
                parentBlock.data.blocks = [
                  ...parentBlock.data.blocks.slice(0, idx + 1),
                  block,
                  ...parentBlock.data.blocks.slice(idx + 1)
                ]
              } else {
                parentBlock.data.blocks = [
                  block,
                  ...parentBlock.data.blocks
                ]
              }
            }
          }
          return
        }

        /*
        ** Block is moved after another block, but not to a columns object
        */
        if (after) {
          const p = this.innerValue.find(b => b.uid === after)
          if (!p) {
            if (this.innerValue.length) {
              console.error('--- NO UID FOR "AFTER"-BLOCK')
              this.innerValue = [
                ...this.innerValue,
                block
              ]
              return
            } else {
              this.innerValue = [
                block
              ]
              return
            }
          }
          const parentIdx = this.innerValue.indexOf(p)

          if (parentIdx + 1 === this.innerValue.length) {
            // index is last, just add to list
            this.innerValue = [
              ...this.innerValue,
              block
            ]
            return
          }

          // we're adding in the midst of things
          this.innerValue = [
            ...this.innerValue.slice(0, parentIdx + 1),
            block,
            ...this.innerValue.slice(parentIdx + 1)
          ]
        }
      })
    },

    duplicateBlock (srcBlock) {
      const { uid } = srcBlock
      const copyBlock = this.$utils.clone(srcBlock)
      copyBlock.uid = this.createUID()

      const block = this.innerValue.find(b => {
        if (b.type === 'columns') {
          for (const col of b.data) {
            for (const colBlock of col.data) {
              if (colBlock.uid === uid) {
                col.data = [
                  ...col.data,
                  copyBlock
                ]
              }
            }
          }
        }
        return b.uid === uid
      })

      if (block) {
        const idx = this.innerValue.indexOf(block)
        this.innerValue = [
          ...this.innerValue.slice(0, idx),
          block,
          copyBlock,
          ...this.innerValue.slice(idx + 1)
        ]
        this.$toast.success({ message: this.$t('block-duplicated') })
      }
    },

    showBlock (bl) {
      const {uid, ref} = bl
      const block = this.innerValue.find(b => {
        if (b.type === 'columns') {
          // look through the columns' blocks and hide if found
          for (const col of b.data) {
            for (const colBlock of col.data) {
              if (colBlock.uid === uid) {
                this.$set(colBlock, 'hidden', false)
              }
            }
          }
        } else if (b.type === 'container') {
          // look through the container's blocks and hide if found
          for (const containedBlock of b.data.blocks) {
            if (containedBlock.uid === uid) {
              if (ref && containedBlock.type === 'module') {
                // we want a ref inside a module block
                const foundRef = containedBlock.data.refs.find(r => r.name === ref)
                this.$set(foundRef, 'hidden', false)
              } else {
                this.$set(containedBlock, 'hidden', false)
              }

            }
          }
        }
        return b.uid === uid
      })

      if (block) {
        if (ref) {
          const idx = this.innerValue.indexOf(block)
          // a ModuleBlock that wants to hide a ref
          const foundRef = block.data.refs.find(r => r.name === ref)
          const refIdx = block.data.refs.indexOf(foundRef)

          this.$set(foundRef, 'hidden', false)

          if (refIdx > -1) {
            this.innerValue = [
              ...this.innerValue.slice(0, idx),
              {
                ...block,
                data: {
                  ...block.data,
                  refs: [
                    ...block.data.refs.slice(0, refIdx),
                    { ...foundRef, hidden: false },
                    ...block.data.refs.slice(refIdx + 1)
                  ]
                }
              },
              ...this.innerValue.slice(idx + 1)
            ]
          } else {
            console.error('showBlock: ref not found...', ref)
          }
        } else {
          this.$set(block, 'hidden', false)
        }
      }
    },

    hideBlock (bl) {
      const {uid, ref} = bl
      const block = this.innerValue.find(b => {
        if (b.type === 'columns') {
          // look through the columns' blocks and hide if found
          for (const col of b.data) {
            for (const colBlock of col.data) {
              if (colBlock.uid === uid) {
                this.$set(colBlock, 'hidden', true)
              }
            }
          }
        } else if (b.type === 'container') {
          // look through the container's blocks and hide if found
          for (const containedBlock of b.data.blocks) {
            if (containedBlock.uid === uid) {
              if (ref && containedBlock.type === 'module') {
                // we want a ref inside a module block
                const foundRef = containedBlock.data.refs.find(r => r.name === ref)
                this.$set(foundRef, 'hidden', true)
              } else {
                this.$set(containedBlock, 'hidden', true)
              }

            }
          }
        }
        return b.uid === uid
      })

      if (block) {
        if (ref) {
          const idx = this.innerValue.indexOf(block)
          // a ModuleBlock that wants to hide a ref
          const foundRef = block.data.refs.find(r => r.name === ref)
          const refIdx = block.data.refs.indexOf(foundRef)

          this.$set(foundRef, 'hidden', true)

          if (refIdx > -1) {
            this.innerValue = [
              ...this.innerValue.slice(0, idx),
              {
                ...block,
                data: {
                  ...block.data,
                  refs: [
                    ...block.data.refs.slice(0, refIdx),
                    { ...foundRef, hidden: true },
                    ...block.data.refs.slice(refIdx + 1)
                  ]
                }
              },
              ...this.innerValue.slice(idx + 1)
            ]
          } else {
            console.error('hideBlock: ref not found...', ref)
          }
        } else {
          this.$set(block, 'hidden', true)
        }
      }
    },

    deleteBlock (bl) {
      const { uid, ref } = bl
      const block = this.innerValue.find(b => {
        if (b.type === 'columns') {
          // look through the columns' blocks and delete if found
          for (const col of b.data) {
            for (const colBlock of col.data) {
              if (colBlock.uid === uid) {
                const colIdx = col.data.indexOf(colBlock)
                col.data = [
                  ...col.data.slice(0, colIdx),
                  ...col.data.slice(colIdx + 1)
                ]
              }
            }
          }
        } else if (b.type === 'container') {
          // look through the container's blocks and delete if found
          for (const containedBlock of b.data.blocks) {
            if (containedBlock.uid === uid) {
              const cIdx = b.data.blocks.indexOf(containedBlock)
              b.data.blocks = [
                ...b.data.blocks.slice(0, cIdx),
                ...b.data.blocks.slice(cIdx + 1)
              ]
            }
          }
        }
        return b.uid === uid
      })

      if (block) {
        if (ref) {
          const idx = this.innerValue.indexOf(block)
          // a ModuleBlock that wants to get rid of a ref!
          const foundRef = block.data.refs.find(r => r.name === ref)
          const refIdx = block.data.refs.indexOf(foundRef)

          if (refIdx > -1) {
            this.innerValue = [
              ...this.innerValue.slice(0, idx),
              {
                ...block,
                data: {
                  ...block.data,
                  refs: [
                    ...block.data.refs.slice(0, refIdx),
                    { ...foundRef, deleted: true },
                    ...block.data.refs.slice(refIdx + 1)
                  ]
                }
              },
              ...this.innerValue.slice(idx + 1)
            ]
          } else {
            console.error('deleteBlock: ref not found...', ref)
          }
        } else {
          const idx = this.innerValue.indexOf(block)
          if (idx > -1) {
            this.innerValue = [
              ...this.innerValue.slice(0, idx),
              ...this.innerValue.slice(idx + 1)
            ]
          }
        }
      }
    },

    orderBlocks (blocks) {
      this.innerValue = [...blocks]
    }
  }

}
</script>
<style lang="postcss">
.villain-editor-backdrop {
  z-index: 25;
  background-color: theme(colors.blue);
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  opacity: 0;
  display: none;
}

.villain-editor {
  background: repeating-linear-gradient(
    -45deg,
    #fff,
    #FFF 2px,
    #faeeea 2px,
    #faeeea 3px
  );
  padding-top: 1rem;
  padding-bottom: 1rem;

  &.villain-fullscreen {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    overflow: auto;
    z-index: 999999;
  }

  /* decrease spacing inside modules */
  [data-type="module"] .villain-block-wrapper {
    margin: 0 0 15px 0;
  }

  .villain-editor-autosave-list-popup {
    padding: 2rem 3rem;
    min-width: 650px;
    margin-left: auto;
    margin-right: 0;
    display: -webkit-box;
    display: -ms-flexbox;
    display: flex;
    flex-direction: column;
    align-items: center;
    background-color: white;
    border: 1px solid #eee;
    position: fixed;
    z-index: 99999;
    top: 50%;
    left: 50%;
    transform: translateX(-50%) translateY(-50%);

    strong {
      text-align: right;
      display: block;
      padding-bottom: 2rem;
    }

    .villain-editor-autosave-list-popup-item {
      display: flex;
      min-width: 500px;
      justify-content: space-between;
      align-items: center;
      padding-bottom: .5rem;

      .villain-editor-autosave-list-popup-item-date {
      }
    }
  }

  a.action-button {
    display: inline-block;
    height: 50px;
    border-radius: 33px;
    padding-top: 15px;
    padding-bottom: 14px;
    padding-left: 23px;
    padding-right: 23px;
    border: 1px solid theme(colors.dark) !important;
    line-height: 1;
    font-size: 18px;
  }

  .text-mono {
    font-family: "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
  }

  .container {
    /** OVERRIDE THIS TO PREVENT TEMPLATES FROM SCREWING UP **/
    max-width: 100%;
  }

  .villain-editor-toolbar {
    padding: 0 1rem;
    text-align: center;

    .villain-editor-instructions {
      font-size: 18px;
      padding: .1rem .5rem;
      display: inline-block;
      background-color: theme(colors.villain.blockBackground);
    }

    .villain-editor-controls {
      padding: .35rem .5rem;
      background-color: #fff;
      display: flex;
      justify-content: space-between;

      .svg-icon {
        width: 30px;

        svg {
          fill: theme(colors.peachDarkest);
          &:hover {
            fill: theme(colors.villain.main);
          }
        }
      }

      div {
        padding: 0 .2rem;

        i {
          color: theme(colors.peachDarkest);
          &:hover {
            color: theme(colors.villain.main);
          }
        }
      }
    }
  }

  .villain-editor-source {
    padding: 1rem;
    textarea {
      padding: 1rem;
      width: 100%;
      height: 100%;
      min-height: 500px;
      font-family: "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
      border: 0;
    }
  }
}

.fade-enter-active, .fade-leave-active {
  transition: opacity 650ms;
}
.fade-enter, .fade-leave-to {
  opacity: 0;
}

.fade-fast-enter-active, .fade-fast-leave-active {
  transition: opacity 250ms;
}
.fade-fast-enter, .fade-fast-leave-to {
  opacity: 0;
}

.bounce-enter-active {
  animation: bounce-in .5s;
}

.bounce-leave-active {
  animation: bounce-out .5s;
}

@keyframes bounce-in {
  0% {
    opacity: .5;
    transform: scale(0.85);
  }
  50% {
    opacity: .75;
    transform: scale(1.02);
  }
  100% {
    opacity: 1;
    transform: scale(1);
  }
}

@keyframes bounce-out {
  0% {
    opacity: 1;
    transform: scale(1);
  }
  20% {
    transform: scale(1.001);
  }
  100% {
    opacity: 0;
    transform: scale(0.85);
  }
}

select.form-control {
  clear: both;
  width: 100%;
}

</style>

<i18n>
  {
    "en": {
      "autosaved-versions": "Auto saved versions",
      "restore-this-version": "Restore this version",
      "click-plus-to-add-block": "Click \"+\" to add a content block",
      "close-source-view": "Close source view",
      "open-source-view": "Show source view",
      "close-fullscreen": "Close fullscreen mode",
      "open-fullscreen": "Show fullscreen mode",
      "update": "Update",
      "autosaving": "autosaving...",
      "old-datasource-wrapper": "Old datasource wrapper! This should be moved to your `code` field or source template. Check console for source",
      "old-datasource-type": "Old datasource type specification. Type has been converted from `many` to `list`. Please save the entry to enforce.",
      "replace-with-autosave": "You are replacing your current content with an autosaved version. Are you sure you want to proceed?",
      "block-duplicated": "Block duplicated",
      "show-autosaved-versions": "Show auto saved versions"
    },
    "no": {
      "autosaved-versions": "Autolagrede versjoner",
      "restore-this-version": "Gjenopprett denne versjonen",
      "click-plus-to-add-block": "Trykk på \"+\" under for å legge til en innholdsblokk",
      "close-source-view": "Lukk kildekodevisning",
      "open-source-view": "Vis kildekode",
      "close-fullscreen": "Lukk fullskjermsmodus",
      "open-fullscreen": "Vis fullskjermsmodus",
      "update": "Oppdatér",
      "autosaving": "autolagrer...",
      "old-datasource-wrapper": "Datakilden har et gammelt format. Flytt `wrapper` til datakildens eget felt. Wrapperkode finner du i konsollen OBS! Wrapper nulles ut ved lagring av dette skjemaet!",
      "old-datasource-type": "Datakilden har et gammelt format. Type er konvertert fra `many` til `list`, men blir ikke gjeldene før du lagrer denne siden.",
      "replace-with-autosave": "Du er i ferd med å erstatte innholdet med data fra en autolagret versjon. Er du sikker på at du vil fortsette?",
      "block-duplicated": "Blokken ble duplisert",
      "show-autosaved-versions": "Vis autolagrede versjoner"
    }
  }
</i18n>
