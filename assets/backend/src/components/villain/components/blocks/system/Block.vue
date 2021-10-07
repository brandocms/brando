<template>
  <div
    ref="wrapper"
    class="villain-block-wrapper">
    <div
      ref="content"
      :class="hovering ? 'villain-hover' : ''"
      :data-uid="block.uid"
      :data-type="block.type"
      class="villain-block">
      <div class="villain-block-description">
        <span class="block-type">{{ blockDescription }}</span> &rarr; <slot name="description"></slot>{{ refDescription }}
      </div>
      <slot></slot>
      <div class="villain-block-actions">
        <div
          v-if="!locked"
          ref="handle"
          class="villain-block-action villain-move">
          <FontAwesomeIcon
            v-popover.left="$t('block.move')"
            icon="arrows-alt"
            size="xs"
            fixed-width />
        </div>
        <div
          v-if="hasHelpSlot"
          class="villain-block-action villain-help"
          @click="helpBlock">
          <FontAwesomeIcon
            v-popover.left="$t('block.help')"
            icon="question-circle"
            size="xs"
            fixed-width />
        </div>
        <div
          v-if="!locked"
          class="villain-block-action villain-duplicate"
          @click="duplicateBlock">
          <FontAwesomeIcon
            v-popover.left="$t('block.duplicate')"
            :icon="['far', 'clone']"
            size="xs"
            fixed-width />
        </div>
        <div
          v-if="hasConfigSlot && block.type !== 'module'"
          class="villain-block-action villain-config"
          @click="openConfig">
          <FontAwesomeIcon
            v-popover.left="$t('block.config')"
            icon="cog"
            size="xs"
            fixed-width />
        </div>
        <div
          v-else-if="block.type === 'module'"
          class="villain-block-action villain-config"
          @click="$parent.$refs[`moduleConfig${block.data.id}`].showConfig = true">
          <FontAwesomeIcon
            v-popover.left="$t('module.config')"
            icon="wrench"
            size="xs"
            fixed-width />
        </div>
        <div
          class="villain-block-action villain-delete"
          @click="deleteBlock">
          <FontAwesomeIcon
            v-popover.left="$t('block.delete')"
            :icon="['far', 'times-circle']"
            size="xs"
            fixed-width />
        </div>
        <div
          v-if="block.hidden"
          class="villain-block-action villain-hide"
          @click="showBlock">
          <FontAwesomeIcon
            v-popover.left="$t('block.hidden')"
            :icon="['far', 'eye-slash']"
            size="xs"
            fixed-width />
        </div>
        <div
          v-if="!block.hidden"
          class="villain-block-action villain-hide"
          @click="hideBlock">
          <FontAwesomeIcon
            v-popover.left="$t('block.visible')"
            :icon="['far', 'eye']"
            size="xs"
            fixed-width />
        </div>
      </div>
    </div>

    <div
      v-show="showHelp"
      ref="help"
      class="villain-block villain-block-help">
      <div class="villain-block-help-content">
        <h5>{{ $t('block.helpText') }} &rarr;</h5>

        <div
          v-if="icon"
          class="display-icon">
          <i
            :class="icon"
            class="fa fa-fw" />
        </div>

        <slot name="help" />

        <div class="villain-help-content-buttons">
          <button
            type="button"
            class="btn btn-primary mt-3"
            @click="showHelp = false">
            {{ $t('close') }}
          </button>
        </div>
      </div>
    </div>

    <template v-if="!locked">
      <VillainPlus
        v-if="block.type !== 'columns' || block.type !== 'container'"
        :after="block.uid"
        :parent="parent"
        @add="$emit('add', $event)"
        @move="$emit('move', $event)" />
      <VillainPlus
        v-else
        :after="block.uid"
        @add="$emit('add', $event)"
        @move="$emit('move', $event)" />
    </template>
  </div>
</template>

<script>
export default {

  inject: [
    'available'
  ],
  props: {
    block: {
      type: Object,
      default: () => {}
    },

    parent: {
      type: String,
      default: null
    },

    config: {
      type: Boolean,
      default: false
    },

    icon: {
      type: String,
      default: ''
    },

    showOk: {
      type: Boolean,
      default: false
    }
  },

  data () {
    return {
      showConfig: false,
      showHelp: false,
      dragEl: null,
      hovering: false,
      moving: false,
      refDescription: '',
      width: null
    }
  },

  computed: {
    blockDescription () {
      const foundBlock = this.available.allBlocks.find(b => {
        return b.component.toLowerCase() === this.block.type
      })
      if (foundBlock) {
        return foundBlock.name
      }
      return 'Modul'
    },

    hasConfigSlot () {
      return Object.prototype.hasOwnProperty.call(this.$slots, 'config')
    },

    hasHelpSlot () {
      return Object.prototype.hasOwnProperty.call(this.$slots, 'help')
    },

    locked () {
      return Object.prototype.hasOwnProperty.call(this.block, 'locked') && this.block.locked
    },

    hasConfigListener () {
      return this.$listeners && this.$listeners.config
    }
  },

  watch: {
    help (v) {
      this.showHelp = v
    }
  },

  mounted () {
    this.$refs.content.addEventListener('mouseover', this.onMouseOver)
    this.$refs.content.addEventListener('mouseleave', this.onMouseLeave)

    if (this.$refs.handle) {
      this.$refs.handle.addEventListener('dragstart', this.onDragStart)
      this.$refs.handle.addEventListener('dragend', this.onDragEnd)
      this.$refs.handle.addEventListener('mousedown', this.onMouseDown)
    }

    this.$nextTick(() => {
      if (this.$parent.$el) {
        const desc = this.$parent.$el.dataset.description
        if (desc) {
          this.refDescription = ` // ${desc}`
          return
        }
      }
      this.refDescription = ''
    })
  },

  methods: {
    createUID () {
      return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
    },

    helpBlock () {
      this.showHelp = true
    },

    openConfig () {
      console.error('==> openConfig called!', this.block.type)
    },

    deleteBlock () {
      console.log('deleteBlock', this.block)
      this.$alerts.alertConfirm('OBS!', this.$t('block.deleteConfirm'), data => {
        if (data) {
          this.$emit('delete', this.block)
        }
      })
    },

    hideBlock () {
      this.$emit('hide', this.block)
    },

    showBlock () {
      this.$emit('show', this.block)
    },

    duplicateBlock () {
      this.$alerts.alertConfirm('OBS!', this.$t('block.duplicateConfirm'), data => {
        if (data) {
          this.$emit('duplicate', this.block)
        }
      })
    },

    onDragStart (ev) {
      ev.stopPropagation()

      const data = this.block
      const block = this.$refs.content
      const handle = this.$refs.handle
      const hCR = handle.getBoundingClientRect()

      this.dragEl = document.createElement('div')
      this.dragEl.style.position = 'absolute'
      this.dragEl.style.opacity = '0.6'
      this.dragEl.style.width = '500px'
      this.dragEl.style.height = '75px'
      this.dragEl.style.pointerEvents = 'none'
      this.dragEl.style.backgroundColor = 'gray'
      this.dragEl.style.border = '1px solid #000'

      this.dragEl.style.top = `${block.offsetTop}px`
      this.dragEl.style.left = `${block.offsetLeft}px`

      document.body.appendChild(this.dragEl)

      const jsonData = JSON.stringify(data, null, 2)

      ev.dataTransfer.dropEffect = 'move'
      ev.dataTransfer.setDragImage(this.dragEl, 0, 0)
      ev.dataTransfer.setData('application/villain', jsonData)

      block.classList.add('villain-dragging-block')
    },

    onDragEnd (ev) {
      ev.stopPropagation()

      if (this.$refs.content) {
        // might be removed when recreated in another column
        this.$refs.content.classList.remove('villain-dragging-block')
        this.$refs.handle.setAttribute('draggable', 'false')
      }

      this.dragEl.parentNode.removeChild(this.dragEl)
    },

    onMouseDown (ev) {
      this.$refs.handle.setAttribute('draggable', 'true')
    },

    onMouseOver (ev) {
      ev.stopPropagation()
      this.hovering = true
    },

    onMouseLeave (ev) {
      ev.stopPropagation()
      this.hovering = false
    }
  }
}
</script>

<i18n>
{
  "en": {
    "close": "Close",
    "block.move": "Move block",
    "block.help": "Show help for block",
    "block.duplicate": "Duplicate block",
    "block.config": "Configure block",
    "block.delete": "Delete block",
    "block.hidden": "Block is hidden",
    "block.visible": "Block is visible",
    "block.helpText": "Help text",
    "block.deleteConfirm": "Are you sure you want to delete this block?",
    "block.duplicateConfirm": "Are you sure you want to duplicate this block?",
    "module.config": "Configure module"
  },
  "no": {
    "close": "Lukk",
    "block.move": "Skift blokkens posisjon",
    "block.help": "Vis hjelp for blokken",
    "block.duplicate": "Duplisér blokken",
    "block.config": "Endre blokkens oppsettsvalg",
    "block.delete": "Slett blokken",
    "block.hidden": "Blokken er skjult",
    "block.visible": "Blokken er synlig",
    "block.helpText": "Hjelpetekst",
    "block.deleteConfirm": "Er du sikker på at du vil slette denne blokken?",
    "block.duplicateConfirm": "Er du sikker på at du vil duplisere denne blokken?",
    "module.config": "Endre modulens oppsettsvalg"
  }
}
</i18n>

<style lang="postcss">
.villain-block-wrapper {
  margin: 1rem;
  position: relative;

  &.multi {
    > [data-type="module"] {
      background-color: transparent;
    }
  }
}

.villain-extra-padding {
  .villain-block {
    padding: 2rem 2rem 1rem 0rem;
  }
}

.villain-block {
  background-color: theme(colors.villain.blockBackground);
  padding: 34px 10px 8px;
  min-height: 105px;
  position: relative;
  border: 1px solid theme(colors.villain.blockBorder);
  transition: border 500ms ease;

  input:focus, textarea:focus {
    outline: none !important;
    border: none;
    box-shadow: none;
  }

  textarea {
    background-color: transparent;
  }

  .villain-module-important-variables {
    margin-top: 8px;
  }

  .helpful-actions {
    margin-top: 8px;
    opacity: 0;
    transition: opacity 300ms ease;
    display: flex;
    justify-content: flex-start;
    align-items: flex-end;

    > * {
      margin-left: 2px;
      margin-right: 2px;
    }
  }

  &.villain-drag-element {
    background: #fff;
    box-shadow: 3px 3px #f00 inset, -3px -3px #f00 inset ;
    position: absolute;
    width: 100%;
    z-index: -1;
    opacity: .5;

    .st-block-addition {
      display: none;
    }
  }

  &.villain-dragging-block {
    background: #f6f7f9;
    max-height: 75px;

    & > * {
      opacity: 0 !important;
    }

    &.st-block-addition {
      opacity: 1;
    }
  }

  &.villain-drag-over {
    &.st-block-addition {
      opacity: 0;
    }
  }

  &.villain-hover, &[data-type="container"] {
    border: 1px solid theme(colors.villain.main);

    > .villain-block-actions > * {
      opacity: 1;
    }

    > .helpful-actions {
      opacity: 1;
    }

    > div > .helpful-actions {
      opacity: 1;
    }

    .module-entry > .entry-toolbar > .helpful-actions {
      opacity: 1;
    }

    > .villain-module-description, > .villain-block-description {
      transition: opacity 300ms ease;
      opacity: 1;
    }
  }

  &[data-type="module"] {
    border-radius: 10px;
    > .villain-module-description, > .villain-block-description {
      transition: opacity 300ms ease;
      opacity: 1;
    }
  }

  &.villain-block-help {
    padding: 2rem;

    .villain-block-help-content {
      max-width: 600px;
      margin: 0 auto;
      padding: 2rem;
      font-size: 95%;

      background-color: theme(colors.villain.secondary);

      .villain-help-content-buttons {
        margin: 0 auto;
        text-align: center;
      }
    }
  }

  &[data-type=datatable], &[data-type=slideshow], &[data-type=image] {
    display: flex;
    align-items: center;
    min-height: 150px;
  }

  &[data-type="comment"] {
    background-color: lightyellow;
  }

  &[data-type="columns"] {
    .row {
      .col-2 {
        width: 16%;
        max-width: 16%;
        flex-basis: 16%;
      }
      .col-3 {
        width: 25%;
        max-width: 25%;
        flex-basis: 25%;
      }
      .col-4 {
        width: 33%;
        max-width: 33%;
        flex-basis: 33%;
      }
      .col-6 {
        width: 50%;
        max-width: 50%;
        flex-basis: 50%;
      }
      .col-12 {
        width: 100%;
        max-width: 100%;
        flex-basis: 100%;
      }
    }
  }

  .villain-module-description, .villain-block-description {
    @font mono;
    color: #000;
    font-size: 10px;
    border-radius: 0;
    padding: 8px 8px;
    font-weight: normal;
    display: inline-block;
    position: absolute;
    top: 0;
    left: 0;
    opacity: 0;
    transition: opacity 300ms ease;
    text-transform: uppercase;

    .block-type {
      display: inline-block;
      margin-right: 3px;
      border: 1px solid theme(colors.dark);
      border-radius: 10px;
      padding: 2px 6px 1px;
    }
  }

  .villain-block-info {
    font-size: 8px;
    text-transform: uppercase;
    text-align: right;
    margin-left: 1rem;
    color: #aaa;
    display: none;
  }

  .villain-block-actions {
    position: absolute;
    right: 2px;
    top: 2px;

    display: flex;
    flex-direction: row-reverse;

    > * {
      opacity: 0.5;
      transition: 500ms opacity ease;
    }

    .villain-block-action {
      padding: 3px 6px;
      background-color: transparent;
      color: theme(colors.villain.mainFaded);

      &:hover {
        color: theme(colors.villain.main);
      }
    }
  }
}

.villain-block-image {
  padding: 0;
  width: 100%;

  img {
    min-width: 100%;
  }
}

.villain-image-library {
  > .col-12 {
    width: 100%;
    flex-basis: 100%;
    max-width: 100%;
  }

  &.row {
    flex-wrap: wrap !important;
  }

  .villain-image-table-selected {
    opacity: 0.5;
    cursor: not-allowed;
  }

  table.villain-image-table {
    td {
      border: 0;
      padding: .25rem .25rem .25rem 0;

      &:first-of-type {
        width: 60px;
      }

      &:last-of-type {
        text-align: right;
      }

      img {
        max-width: 46px;
      }

      table {
        margin-bottom: 0;

        td {
          padding: .75rem .75rem;
          font-size: 12px;

        }
      }
    }
  }
  img {
    max-width: 100px;
    padding: .3rem;
    border: 1px solid #dee2e6;
    background-color: #fff;
    cursor: pointer;

    &:hover {
      box-shadow: 0px 0px 5px #85003838;
      border-color: #aaa;
    }
  }
}

.villain-block-video {
  padding-right: 0;

  .villain-block-video-content {
    height: 0;
    padding-top: 56.25%;
    position: relative;
    width: 100%;

    iframe {
      height: 100%;
      left: 0;
      position: absolute;
      top: 0;
      width: 100%;
    }
  }

  video.villain-video-file {
    width: 100%;
  }
}

.fade-move-enter-active,
.fade-move-leave-active {
  transition: opacity 0.3s;
}

.fade-move-enter,
.fade-move-leave-to {
  opacity: 0;
}

.fade-move-move {
  transition: transform 1s;
}

.villain-block-datatable-table {
  tr {
    td {
      border: 0;
      padding: 5px;

      &:first-of-type {
        width: 35%;
      }

      input[type=input] {
        font-size: 90%;
      }
    }
  }
}

.villain-header-input {
  border: 0;
  width: 100%;
  padding: 0;
  line-height: 1.1;
  font-weight: 500;
}

.villain-markdown-input,
.villain-svg-input,
.villain-html-input {
  border: 0;
  width: 100%;
  font-family: "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
}

.villain-svg-output {
  max-width: 250px;
  user-select: none;
  pointer-events: none;
}

.villain-block-divider {
  padding-left: 2rem;
  padding-top: 2rem;

  hr {
    border-bottom: 1px solid #ddd;
    border-left: none;
    border-right: none;
    border-top: none;
    margin: 1.5em 0;
  }
}

.villain-blockquote-content {
  width: 100%;
  border: 0;
  padding: 1.5rem;
  font-size: 2rem;
  font-style: italic;
}

.villain-blockquote-cite {
  width: 100%;
  border: 0;
  padding: 0 1.5rem 1.5rem;
  font-size: 1rem;
  font-style: italic;
}

.villain-svg-input-wrapper {
  width: 100%;
}

.villain-editor, .villain-builder, .kmodal {
  /* BASICS */

  .CodeMirror {
    /* Set height, width, borders, and global font properties here */
    font-family: "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
    font-size: 14px;
    height: auto;
    color: black;
    direction: ltr;
  }

  /* PADDING */

  .CodeMirror-lines {
    padding: 4px 0; /* Vertical padding around content */
  }
  .CodeMirror pre.CodeMirror-line,
  .CodeMirror pre.CodeMirror-line-like {
    padding: 0 4px; /* Horizontal padding of content */
  }

  .CodeMirror-scrollbar-filler, .CodeMirror-gutter-filler {
    background-color: white; /* The little square between H and V scrollbars */
  }

  /* GUTTER */

  .CodeMirror-gutters {
    border-right: 1px solid #ddd;
    background-color: #f7f7f7;
    white-space: nowrap;
  }
  .CodeMirror-linenumbers {}
  .CodeMirror-linenumber {
    padding: 0 20px 0 10px;
    min-width: 20px;
    text-align: right;
    color: #999;
    white-space: nowrap;
  }

  .CodeMirror-guttermarker { color: black; }
  .CodeMirror-guttermarker-subtle { color: #999; }

  /* CURSOR */

  .CodeMirror-cursor {
    border-left: 1px solid black;
    border-right: none;
    width: 0;
  }
  /* Shown when moving in bi-directional text */
  .CodeMirror div.CodeMirror-secondarycursor {
    border-left: 1px solid silver;
  }
  .cm-fat-cursor .CodeMirror-cursor {
    width: auto;
    border: 0 !important;
    background: #7e7;
  }
  .cm-fat-cursor div.CodeMirror-cursors {
    z-index: 1;
  }
  .cm-fat-cursor-mark {
    background-color: rgba(20, 255, 20, 0.5);
    -webkit-animation: blink 1.06s steps(1) infinite;
    -moz-animation: blink 1.06s steps(1) infinite;
    animation: blink 1.06s steps(1) infinite;
  }
  .cm-animate-fat-cursor {
    width: auto;
    border: 0;
    -webkit-animation: blink 1.06s steps(1) infinite;
    -moz-animation: blink 1.06s steps(1) infinite;
    animation: blink 1.06s steps(1) infinite;
    background-color: #7e7;
  }

  /* Can style cursor different in overwrite (non-insert) mode */
  .CodeMirror-overwrite .CodeMirror-cursor {}

  .cm-tab { display: inline-block; text-decoration: inherit; }

  .CodeMirror-rulers {
    position: absolute;
    left: 0; right: 0; top: -50px; bottom: 0;
    overflow: hidden;
  }
  .CodeMirror-ruler {
    border-left: 1px solid #ccc;
    top: 0; bottom: 0;
    position: absolute;
  }

  /* DEFAULT THEME */

  .cm-s-default .cm-header {color: blue;}
  .cm-s-default .cm-quote {color: #090;}
  .cm-negative {color: #d44;}
  .cm-positive {color: #292;}
  .cm-header, .cm-strong {font-weight: bold;}
  .cm-em {font-style: italic;}
  .cm-link {text-decoration: underline;}
  .cm-strikethrough {text-decoration: line-through;}

  .cm-s-default .cm-keyword {color: #708;}
  .cm-s-default .cm-atom {color: #219;}
  .cm-s-default .cm-number {color: #164;}
  .cm-s-default .cm-def {color: #00f;}
  .cm-s-default .cm-variable,
  .cm-s-default .cm-punctuation,
  .cm-s-default .cm-property,
  .cm-s-default .cm-operator {}
  .cm-s-default .cm-variable-2 {color: #05a;}
  .cm-s-default .cm-variable-3, .cm-s-default .cm-type {color: #085;}
  .cm-s-default .cm-comment {color: #a50;}
  .cm-s-default .cm-string {color: #a11;}
  .cm-s-default .cm-string-2 {color: #f50;}
  .cm-s-default .cm-meta {color: #555;}
  .cm-s-default .cm-qualifier {color: #555;}
  .cm-s-default .cm-builtin {color: #30a;}
  .cm-s-default .cm-bracket {color: #997;}
  .cm-s-default .cm-tag {color: #170;}
  .cm-s-default .cm-attribute {color: #00c;}
  .cm-s-default .cm-hr {color: #999;}
  .cm-s-default .cm-link {color: #00c;}

  .cm-s-default .cm-error {color: #f00;}
  .cm-invalidchar {color: #f00;}

  .CodeMirror-composing { border-bottom: 2px solid; }

  /* Default styles for common addons */

  div.CodeMirror span.CodeMirror-matchingbracket {color: #0b0;}
  div.CodeMirror span.CodeMirror-nonmatchingbracket {color: #a22;}
  .CodeMirror-matchingtag { background: rgba(255, 150, 0, .3); }
  .CodeMirror-activeline-background {background: #e8f2ff;}

  /* STOP */

  /* The rest of this file contains styles related to the mechanics of
     the editor. You probably shouldn't touch them. */

  .CodeMirror {
    display: grid;
    position: relative;
    overflow: hidden;
    background: white;
  }

  .CodeMirror-scroll {
    overflow: scroll !important; /* Things will break if this is overridden */
    /* 30px is the magic margin used to hide the element's real scrollbars */
    /* See overflow: hidden in .CodeMirror */
    margin-bottom: -30px; margin-right: -30px;
    padding-bottom: 30px;
    height: 100%;
    outline: none; /* Prevent dragging from highlighting the element */
    position: relative;
  }
  .CodeMirror-sizer {
    position: relative;
    border-right: 30px solid transparent;
  }

  /* The fake, visible scrollbars. Used to force redraw during scrolling
     before actual scrolling happens, thus preventing shaking and
     flickering artifacts. */
  .CodeMirror-vscrollbar, .CodeMirror-hscrollbar, .CodeMirror-scrollbar-filler, .CodeMirror-gutter-filler {
    position: absolute;
    z-index: 6;
    display: none;
  }
  .CodeMirror-vscrollbar {
    right: 0; top: 0;
    overflow-x: hidden;
    overflow-y: scroll;
  }
  .CodeMirror-hscrollbar {
    bottom: 0; left: 0;
    overflow-y: hidden;
    overflow-x: scroll;
  }
  .CodeMirror-scrollbar-filler {
    right: 0; bottom: 0;
  }
  .CodeMirror-gutter-filler {
    left: 0; bottom: 0;
  }

  .CodeMirror-gutters {
    position: absolute; left: 0; top: 0;
    min-height: 100%;
    z-index: 3;
  }
  .CodeMirror-gutter {
    white-space: normal;
    height: 100%;
    display: inline-block;
    vertical-align: top;
    margin-bottom: -30px;
  }
  .CodeMirror-gutter-wrapper {
    position: absolute;
    z-index: 4;
    background: none !important;
    border: none !important;
  }
  .CodeMirror-gutter-background {
    position: absolute;
    top: 0; bottom: 0;
    z-index: 4;
  }
  .CodeMirror-gutter-elt {
    position: absolute;
    cursor: default;
    z-index: 4;
  }
  .CodeMirror-gutter-wrapper ::selection { background-color: transparent }
  .CodeMirror-gutter-wrapper ::-moz-selection { background-color: transparent }

  .CodeMirror-lines {
    cursor: text;
    min-height: 1px; /* prevents collapsing before first draw */
  }
  .CodeMirror pre.CodeMirror-line,
  .CodeMirror pre.CodeMirror-line-like {
    /* Reset some styles that the rest of the page might have set */
    -moz-border-radius: 0; -webkit-border-radius: 0; border-radius: 0;
    border-width: 0;
    background: transparent;
    font-family: inherit;
    font-size: inherit;
    margin: 0;
    white-space: pre;
    word-wrap: normal;
    line-height: inherit;
    color: inherit;
    z-index: 2;
    position: relative;
    overflow: visible;
    -webkit-tap-highlight-color: transparent;
    -webkit-font-variant-ligatures: contextual;
    font-variant-ligatures: contextual;
  }
  .CodeMirror-wrap pre.CodeMirror-line,
  .CodeMirror-wrap pre.CodeMirror-line-like {
    word-wrap: break-word;
    white-space: pre-wrap;
    word-break: normal;
  }

  .CodeMirror-linebackground {
    position: absolute;
    left: 0; right: 0; top: 0; bottom: 0;
    z-index: 0;
  }

  .CodeMirror-linewidget {
    position: relative;
    z-index: 2;
    padding: 0.1px; /* Force widget margins to stay inside of the container */
  }

  .CodeMirror-rtl pre { direction: rtl; }

  .CodeMirror-code {
    outline: none;
  }

  /* Force content-box sizing for the elements where we expect it */
  .CodeMirror-scroll,
  .CodeMirror-sizer,
  .CodeMirror-gutter,
  .CodeMirror-gutters,
  .CodeMirror-linenumber {
    -moz-box-sizing: content-box;
    box-sizing: content-box;
  }

  .CodeMirror-measure {
    position: absolute;
    width: 100%;
    height: 0;
    overflow: hidden;
    visibility: hidden;
  }

  .CodeMirror-cursor {
    position: absolute;
    pointer-events: none;
  }
  .CodeMirror-measure pre { position: static; }

  div.CodeMirror-cursors {
    visibility: hidden;
    position: relative;
    z-index: 3;
  }
  div.CodeMirror-dragcursors {
    visibility: visible;
  }

  .CodeMirror-focused div.CodeMirror-cursors {
    visibility: visible;
  }

  .CodeMirror-selected { background: #d9d9d9; }
  .CodeMirror-focused .CodeMirror-selected { background: #d7d4f0; }
  .CodeMirror-crosshair { cursor: crosshair; }
  .CodeMirror-line::selection, .CodeMirror-line > span::selection, .CodeMirror-line > span > span::selection { background: #d7d4f0; }
  .CodeMirror-line::-moz-selection, .CodeMirror-line > span::-moz-selection, .CodeMirror-line > span > span::-moz-selection { background: #d7d4f0; }

  .cm-searching {
    background-color: #ffa;
    background-color: rgba(255, 255, 0, .4);
  }

  /* Used to force a border model for a node */
  .cm-force-border { padding-right: .1px; }

  @media print {
    /* Hide the cursor when printing */
    .CodeMirror div.CodeMirror-cursors {
      visibility: hidden;
    }
  }

  /* See issue #2901 */
  .cm-tab-wrap-hack:after { content: ''; }

  /* Help users use markselection to safely style text background */
  span.CodeMirror-selectedtext { background: none; }

  /*
Name:   DuoTone-Light
Author: by Bram de Haan, adapted from DuoTone themes by Simurai (http://simurai.com/projects/2016/01/01/duotone-themes)

CodeMirror template by Jan T. Sott (https://github.com/idleberg), adapted by Bram de Haan (https://github.com/atelierbram/)
*/

.cm-s-duotone-light.CodeMirror { background: #ffffff; color: #021853; }
.cm-s-duotone-light div.CodeMirror-selected { background: #e3dcce !important; }
.cm-s-duotone-light .CodeMirror-gutters { background: #ffffff; border-right: 0px; }
.cm-s-duotone-light .CodeMirror-linenumber {
  height: 100%;
  color: #c1c1c1;
  font-size: 12px;
  line-height: 20px;
  text-align: center;
}

/* begin cursor */
.cm-s-duotone-light .CodeMirror-cursor { border-left: 1px solid #93abdc; /* border-left: 1px solid #93abdc80; */ border-right: .5em solid #93abdc; /* border-right: .5em solid #93abdc80; */ opacity: .5; }
.cm-s-duotone-light .CodeMirror-activeline-background { background: #e3dcce;  /* background: #e3dcce80; */ opacity: .5; }
.cm-s-duotone-light .cm-fat-cursor .CodeMirror-cursor { background: #93abdc; /* #93abdc80; */ opacity: .5; }
/* end cursor */

.cm-s-duotone-light span.cm-atom, .cm-s-duotone-light span.cm-number, .cm-s-duotone-light span.cm-keyword, .cm-s-duotone-light span.cm-variable, .cm-s-duotone-light span.cm-attribute, .cm-s-duotone-light span.cm-quote, .cm-s-duotone-light-light span.cm-hr, .cm-s-duotone-light-light span.cm-link { color: #063289; }

.cm-s-duotone-light span.cm-property { color: #b29762; }
.cm-s-duotone-light span.cm-punctuation, .cm-s-duotone-light span.cm-unit, .cm-s-duotone-light span.cm-negative { color: #063289; }
.cm-s-duotone-light span.cm-string, .cm-s-duotone-light span.cm-operator { color: #1659df; }
.cm-s-duotone-light span.cm-positive { color: #896724; }

.cm-s-duotone-light span.cm-variable-2, .cm-s-duotone-light span.cm-variable-3, .cm-s-duotone-light span.cm-type, .cm-s-duotone-light span.cm-string-2, .cm-s-duotone-light span.cm-url { color: #896724; }
.cm-s-duotone-light span.cm-def, .cm-s-duotone-light span.cm-tag, .cm-s-duotone-light span.cm-builtin, .cm-s-duotone-light span.cm-qualifier, .cm-s-duotone-light span.cm-header, .cm-s-duotone-light span.cm-em { color: #2d2006; }
.cm-s-duotone-light span.cm-bracket, .cm-s-duotone-light span.cm-comment { color: #b6ad9a; }

/* using #f00 red for errors, don't think any of the colorscheme variables will stand out enough, ... maybe by giving it a background-color ... */
/* .cm-s-duotone-light span.cm-error { background: #896724; color: #728fcb; } */
.cm-s-duotone-light span.cm-error, .cm-s-duotone-light span.cm-invalidchar { color: #f00; }

.cm-s-duotone-light span.cm-header { font-weight: normal; }
.cm-s-duotone-light .CodeMirror-matchingbracket { text-decoration: underline; color: #faf8f5 !important; }
}

</style>
