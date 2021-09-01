<template>
  <Block
    :block="block"
    :parent="parent"
    :class="{ multi: block.data.multi }"
    @add="$emit('add', $event)"
    @move="$emit('move', $event)"
    @duplicate="$emit('duplicate', $event)"
    @hide="$emit('hide', $event)"
    @show="$emit('show', $event)"
    @delete="$emit('delete', $event)">
    <template #description>
      {{ getBlockName }}{{ block.data.multi ? ' — Multi' : '' }}
    </template>
    <ModuleImportantVariables
      v-if="!block.data.multi"
      v-model="block.data.vars" />
    <div
      v-if="!block.data.multi"
      class="module-entry"
      @click="handleClick">
      <component
        :is="buildWrapper({refs: block.data.refs, vars: block.data.vars})"
        @delete="deleteBlock($event)"
        @hide="hideBlock($event)"
        @show="showBlock($event)"
        @update="updateBlock($event)" />
      <div class="entry-toolbar">
        <div class="helpful-actions">
          <ModuleConfig
            :ref="`moduleConfig${block.data.id}`"
            :module-id="block.data.id"
            :refs="block.data.refs"
            :vars="block.data.vars"
            @updateVars="updateVars"
            @updateRefs="updateRefs" />
        </div>
      </div>
    </div>
    <template v-else>
      <transition-group
        v-if="block.data.entries"
        v-sortable="{
          handle: '.module-entry',
          animation: 0,
          store: {
            get: getOrder,
            set: storeOrder
          }}"
        name="fade-fast"
        tag="div"
        class="sort-container">
        <div
          v-for="entry in block.data.entries"
          :key="entry.id"
          :data-id="entry.id"
          class="module-entry"
          @click="handleClick">
          <ModuleImportantVariables
            v-model="entry.vars" />
          <component
            :is="buildWrapper(entry)"
            @delete="deleteBlock($event)"
            @update="updateBlock($event)" />
          <div class="entry-toolbar">
            <div class="helpful-actions">
              <ButtonTiny
                right
                @click="deleteEntry(entry)">
                {{ $t('delete') }}
              </ButtonTiny>
              <ModuleConfig
                :ref="`moduleConfig${entry.id}`"
                :module-id="block.data.id"
                :entry-id="entry.id"
                :refs="entry.refs"
                :vars="entry.vars"
                @updateVars="updateVars"
                @updateRefs="updateRefs" />
            </div>
          </div>
        </div>
      </transition-group>
    </template>

    <div v-if="block.data.multi">
      <div
        class="add-multi-entry"
        @click="addMultiEntry">
        {{ $t('add-new-object-in') }} &laquo;{{ getBlockName }}&raquo;
      </div>
    </div>
  </Block>
</template>

<script>

import ModuleConfig from './ModuleConfig'
import ModuleImportantVariables from './ModuleImportantVariables'
import IconRefresh from '../../icons/IconRefresh'
import cloneDeep from 'lodash/cloneDeep'
import camelCase from 'lodash/camelCase'
import shortid from 'shortid'

export default {
  name: 'ModuleBlock',

  components: {
    IconRefresh,
    ModuleConfig,
    ModuleImportantVariables
  },

  inject: [
    'available',
    'refresh'
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
      showConfig: false,
      customClass: '',
      uid: null,
      hasImportantVariables: false
    }
  },

  computed: {
    getBlockName () {
      if (this.block.data.name) {
        return this.block.data.name
      }

      let foundModule
      const id = this.block.data.id

      if (id) {
        foundModule = this.available.modules.find(t => t.data.id === id)
      }

      if (!foundModule) {
        return '?'
      }

      return foundModule.data.name
    },

    /**
     * Check if refs has `entries` key, that means we have converted it
     * to a multi.
     */
    hasEntries () {
      return Object.prototype.hasOwnProperty.call(this.block.data, 'entries')
    }
  },

  created () {
    this.deleteProps()

    // if this is a multi but refs is not an array of arrays
    // we convert.

    if (this.block.data.multi && !this.hasEntries) {
      this.$set(this.block.data, 'entries', [{
        id: shortid.generate(),
        refs: this.block.data.refs,
        vars: this.block.data.vars
      }])
      delete this.block.data.refs
    }

    this.hasImportantVariables = false

    for (const [key, value] of Object.entries(this.block.data.vars)) {
      if (value.important) {
        console.log('-- has important variables.')
        this.hasImportantVariables = true
        break
      }
    }

    // check if any refs are missing
  },

  methods: {
    getOrder () {
      return this.block.data.entries
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray()

      var arr = this.block.data.entries.sort((a, b) => {
        return this.sortedArray.indexOf(a.id) - this.sortedArray.indexOf(b.id)
      })

      this.$set(this.block.data, 'entries', arr)
      // this.$emit('sort', this.sortedArray)
    },

    handleClick (e) {
      if (e.target.matches('[data-type="module"] *')) {
        e.preventDefault()
      }
    },

    buildWrapper (entry) {
      const replacedContent = this.replaceContent(entry)
      const builtSlots = this.buildSlots(entry.refs)

      const template = `
        <component
          :is="buildCmp()"
          :entry-data="entryData">
          ${replacedContent}
          ${builtSlots}
        </component>
      `

      const data = this.buildData(entry.refs)
      const entryData = this.available.entryData

      const replaceMediaBlock = ({ mref, newBlock }) => {
        if (entry.id) {
          // a MULTI
          //!TODO: Handle replacing media blocks inside multi tpls
        } else {
          const oldMediaRef = this.findRef(mref, entry.refs)
          const newRef = { ...oldMediaRef, data: newBlock }
          const idx = entry.refs.indexOf(oldMediaRef)

          if (idx > -1) {
            const newRefs = [
              ...entry.refs.slice(0, idx),
              newRef,
              ...entry.refs.slice(idx + 1)
            ]

            this.$set(entry, 'refs', newRefs)
            this.$set(this.block.data, 'refs', newRefs)
          }
        }
      }

      return {
        name: 'BuildWrapper',
        delimiters: ['%%%', '%%%'],
        template,
        data () {
          return data
        },
        methods: {
          buildCmp () {
            return {
              name: 'BuiltComponent',
              data () {
                return {
                  entryData: entryData
                }
              },
              methods: {
                replace (payload) {
                  replaceMediaBlock(payload)
                }
              },
              delimiters: ['%%%%', '%%%%'],
              template: `
                <div>${replacedContent}</div>
              `
            }
          }
        }
      }
    },

    findModule () {
      const id = this.block.data.id

      if (id) {
        return this.available.modules.find(t => t.data.id === id)
      }
    },

    deleteEntry (entry) {
      this.$delete(this.block.data.entries, this.block.data.entries.indexOf(entry))
    },

    replaceContent (entry) {
      const srcCode = this.getSourceCode()
      // throw out logic(?)
      const srcWithReplacedLogic = this.replaceLogic(srcCode)
      // replace all variables
      const srcWithReplacedEntry = this.replaceEntries(srcWithReplacedLogic)
      const srcWithReplacedVars = this.replaceVars(srcWithReplacedEntry, entry)
      // replace all refs
      const srcWithReplacedVarsRefs = this.replaceRefs(srcWithReplacedVars, entry)
      return srcWithReplacedVarsRefs
    },

    replaceLogic (srcCode) {
      let replacedLogicCode = srcCode.replace(/(\{% for (\w+) in [a-zA-Z0-9.?|"-]+ %\})(.*?)(\{% endfor %\})/gs, this.replaceEmpty)
      replacedLogicCode = replacedLogicCode.replace(/(\{% assign .*? %\})/gs, this.replaceEmpty)
      replacedLogicCode = replacedLogicCode.replace(/\{% comment %\}((.|\n)*?)\{% endcomment %\}/gs, this.replaceCommentLogic)
      replacedLogicCode = replacedLogicCode.replace(/\{% hide %\}((.|\n)*?)\{% endhide %\}/gs, this.replaceEmpty)
      replacedLogicCode = replacedLogicCode.replace(/(\{% if [a-zA-Z0-9.?|_"-]+ (==|!=) [a-zA-Z0-9.?|_"-]+ %\}(.|\n)*?\{% endif %\})/sg, '')
      replacedLogicCode = replacedLogicCode.replace(/(\{% if [a-zA-Z0-9.?|_"-]+ %\}(.|\n)*?\{% endif %\})/sg, '')
      return replacedLogicCode
    },

    replaceCommentLogic (exp, comment) {
      return `<span v-popover="''" class="villain-entry-comment"><span v-pre>${comment}</span></span>`
    },

    replaceEmpty (exp, f) {
      return ''
    },

    replaceVars (srcCode, entry) {
      // TODO: when lookbehind is implemented: /(?<!<\/?[^>]*|&[^;]*)(\${.*?})/g
      const replacedVarsCode = srcCode.replace(/<.*?>|\{\{\s?(.*?)\s?\}\}/gs, (exp, varName) => this.replaceVar(exp, varName, entry))
      return replacedVarsCode
    },

    replaceVar (exp, varName, entry) {
      if (varName) {
        return `<span v-popover="'Skiftes automatisk ut med en verdi når objektet lagres'" class="villain-entry-var"><span v-pre>${varName}</span></span>`
      }

      return exp
    },

    updateVars ({ newVars, entryId }) {
      if (entryId) {
        const entry = this.findEntry(entryId)
        if (entry) {
          this.$set(entry, 'vars', newVars)
        }
      } else {
        this.$set(this.block.data, 'vars', newVars)
      }
    },

    replaceEntries (srcCode) {
      const replacedEntriesCode = srcCode.replace(/\{\{ entry.(\w+) \}}/g, this.replaceEntry)
      return replacedEntriesCode
    },

    replaceEntry (exp, entryVar) {
      if (this.available.entryData) {
        return `<span v-popover="'{{ entry.${entryVar} }}'" class="villain-entry-var" data-villain-var>${this.lookupEntryVar(entryVar)}</span>`
      } else {
        return `<span v-popover="'Skiftes automatisk ut med en verdi når objektet lagres'" class="villain-entry-var"><span v-pre>entry.${entryVar}</span></span>`
      }
    },

    lookupEntryVar (entryVar) {
      const camelCasedVar = camelCase(entryVar)
      if (this.available.entryData[entryVar]) {
        return this.available.entryData[entryVar]
      } else {
        return `ukjent variabel: entry.${entryVar}`
      }
    },

    updateRefs ({ newRefs, entryId }) {
      if (entryId) {
        const entry = this.findEntry(entryId)
        if (entry) {
          this.$set(entry, 'refs', newRefs)
        }
      } else {
        this.$set(this.block.data, 'refs', newRefs)
      }
    },

    replaceRefs (srcCode, entry) {
      const replacedRefsCode = srcCode.replace(/%{(\w+)}/g, (exp, refName) => {
        return this.replaceRef(exp, refName, entry)
      })

      return replacedRefsCode
    },

    replaceRef (exp, refName, entry) {
      let ref = this.findRef(refName, entry.refs)

      if (!ref) {
        // ref not found —— the module might have been updated.
        const t = this.findModule()
        ref = this.findRef(refName, t.data.refs)
        const newRefs = [ ...entry.refs, ref ]
        this.$set(entry, 'refs', newRefs)
        this.$set(this.block.data, 'refs', newRefs)
      }

      if (ref.deleted) {
        return ''
      }

      return `<slot name="${refName}"></slot>`
    },

    findRef (refName, refs) {
      return refs.find(r => r.name === refName)
    },

    findEntry (entryId) {
      return this.block.data.entries.find(e => e.id === entryId)
    },

    addMultiEntry () {
      const foundModule = this.available.modules.find(t => t.data.id === this.block.data.id)
      this.$set(this.block.data, 'entries', [
        ...this.block.data.entries, {
          id: shortid.generate(),
          refs: cloneDeep(foundModule.data.refs),
          vars: cloneDeep(foundModule.data.vars)
        }
      ])
    },

    /** remove props we don't want to store */
    deleteProps () {
      // only delete props here if we have an ID
      if (!Object.prototype.hasOwnProperty.call(this.block.data, 'id')) {
        return
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'namespace')) {
        this.$delete(this.block.data, 'namespace')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'code')) {
        this.$delete(this.block.data, 'code')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'wrapper')) {
        this.$delete(this.block.data, 'wrapper')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'class')) {
        this.$delete(this.block.data, 'class')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'name')) {
        this.$delete(this.block.data, 'name')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'svg')) {
        this.$delete(this.block.data, 'svg')
      }

      if (Object.prototype.hasOwnProperty.call(this.block.data, 'help_text')) {
        this.$delete(this.block.data, 'help_text')
      }
    },

    getSourceCode () {
      let foundModule
      const id = this.block.data.id

      if (!id) {
        foundModule = this.available.modules.find(t => t.data.class === this.block.data.class)
      } else {
        foundModule = this.available.modules.find(t => t.data.id === id)
      }

      if (!foundModule) {
        console.error('==> missing module', this.block.data)
        return '<div>!! module not found !!</div>'
      }

      this.$set(this.block.data, 'id', foundModule.data.id)
      this.deleteProps()
      return foundModule.data.code
    },

    findVar (varName, entry) {
      console.error('==> findVar')
      if (!entry.vars) {
        return null
      }

      if (Object.prototype.hasOwnProperty.call(entry.vars, varName)) {
        return entry.vars[varName].value
      }

      return null
    },

    buildData (refs) {
      // build it by {refname: data}
      const newRefs = {}
      for (let i = 0; i < refs.length; i++) {
        const ref = refs[i]
        if (ref.deleted) {
          continue
        }
        newRefs[ref.name] = {
          ...ref.data,
          hidden: ref.hidden || false,
          locked: true
        }
      }

      return {
        refs: newRefs,
        entryData: this.available.entryData
      }
    },

    buildSlots (refs, copyMissing = true) {
      let module = ''
      if (copyMissing) {
        this.copyMissingRefs(refs)
      }

      for (let i = 0; i < refs.length; i++) {
        const ref = refs[i]
        if (ref.deleted) {
          continue
        }
        module += `
          <div slot="${ref.name}">
            <component
              is="${ref.data.type}Block"
              data-description="${ref.description || ''}"
              data-ref="${ref.name}"
              :block="refs.${ref.name}"
              :mref="'${ref.name}'"
              @hide="$emit('hide', {event: $event, ref: '${ref.name}'})"
              @show="$emit('show', {event: $event, ref: '${ref.name}'})"
              @delete="$emit('delete', {event: $event, ref: '${ref.name}'})" />
          </div>
        `
      }
      return module
    },

    copyMissingRefs (refs) {
      let foundModule
      const id = this.block.data.id

      if (!id) {
        foundModule = this.available.modules.find(t => t.data.class === this.block.data.class)
      } else {
        foundModule = this.available.modules.find(t => parseInt(t.data.id) === parseInt(id))
      }

      if (!foundModule) {
        console.error('VILLAIN: module not found')
        return
      }

      const moduleSourceRefs = foundModule.data.refs
      const blockRefs = refs

      for (let i = 0; i < moduleSourceRefs.length; i++) {
        if (!blockRefs.find(b => b.name === moduleSourceRefs[i].name)) {
          refs = [
            ...refs,
            moduleSourceRefs[i]
          ]
        }
      }
    },

    showBlock ({ ref, block }) {
      this.$emit('show', { ...this.block, ref })
    },

    hideBlock ({ ref, block }) {
      this.$emit('hide', { ...this.block, ref })
    },

    deleteBlock ({ ref, block }) {
      this.$emit('delete', { ...this.block, ref })
    }
  }
}
</script>
<style lang="postcss" scoped>

  .module-entry {
    margin-bottom: 8px;
    padding: 8px;
    background-color: #fbf5f2;

    .multi .sort-container & {
      &:first-of-type {
        margin-top: 0;
      }
      margin-top: 1rem;
    }
  }

  .villain-module-important-config {
    background-color: #faffd0;
    border: 1px solid #eee;
    padding: 20px;
    margin-bottom: 14px;
    font-size: 17px;
    font-weight: 500;

    svg {
      border: 1px solid;
      background-color: white;
      padding: 4px;
      border-radius: 7px;
      margin-right: 7px;
    }
  }

  .entry-toolbar {
    display: flex;
    justify-content: flex-end;
    align-items: baseline;

    .helpful-actions {
      margin-top: 0;
    }

    > * + * {
      margin-left: 0.25rem;
    }
  }

  .add-multi-entry {
    @font mono xs/1;
    border: 1px solid #1a47ff;
    padding: 1rem;
    background-color: #ffffff;
    margin-top: 1rem;
    text-align: center;
    text-transform: uppercase;
    cursor: pointer;
    display: inline-block;
    margin: 0 auto;
    text-align: center;

    &:hover {
      background-color: #1a47ff;
      color: #ffffff;
    }
  }

  >>> .villain-entry-var {
    padding: 4px 5px;
    background-color: gold;
    font-family: mono;
    font-size: 12px;
    border-radius: 7px;

    &:hover {
      border-radius: 5px;
      background-color: yellow;
      cursor: help;
    }
  }

  >>> .villain-entry-comment {
    padding: 4px 5px;
    background-color: pink;
    font-family: mono;
    font-size: 12px;
    border-radius: 7px;

    &:hover {
      border-radius: 5px;
      background-color: pink;
      cursor: help;
    }
  }
</style>
<i18n>
  {
    "en": {
      "delete": "Delete",
      "add-new-object-in": "Add new entry to"
    },
    "no": {
      "delete": "Slett",
      "add-new-object-in": "Legg til nytt objekt i"
    }
  }
</i18n>
