<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :maxlength="maxlength"
    :help-text="helpText"
    :value="value">
    <template #default>
      <div
        ref="wrapper"
        class="code-input-wrapper"
        :class="{ transparent }">
        <textarea
          ref="txt"
          :rows="rows"
          class="code-input"></textarea>
      </div>
      <input
        :id="id"
        ref="input"
        v-model="innerValue"
        :name="name"
        type="hidden">
    </template>
  </KFieldBase>
</template>

<script>
import CodeMirror from 'codemirror'
import 'codemirror/addon/display/autorefresh.js'
import 'codemirror/addon/mode/overlay'

export default {
  props: {
    disabled: {
      type: Boolean,
      default: false
    },

    transparent: {
      type: Boolean,
      default: false
    },

    lineNumbers: {
      type: Boolean,
      default: true
    },

    rows: {
      type: Number,
      default: 5
    },

    helpText: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: false,
      default: null
    },

    maxlength: {
      type: Number,
      default: null
    },

    placeholder: {
      type: String,
      required: false,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    monospace: {
      type: Boolean,
      default: false
    },

    invert: {
      type: Boolean,
      default: false
    },

    name: {
      type: String,
      required: true
    },

    value: {
      type: [String, Number],
      default: ''
    }
  },

  data () {
    return {
      editor: null,
      customClass: '',
      linkUrl: null,
      linkMenuIsActive: false,
      actionButtonUrl: null,
      actionButtonMenuIsActive: false
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    },

    innerValue: {
      get () { return this.value },
      set (innerValue) {
        this.$emit('input', innerValue)
      }
    }
  },

  created () {
    this.$nextTick(() => {
      this.bindEditor()
    })
  },

  destroy () {
    // garbage cleanup
    const element = this.codeMirror.doc.cm.getWrapperElement()
    element && element.remove && element.remove()
  },

  methods: {
    bindEditor () {
      CodeMirror.defineMode('htmltwig', function (config, parserConfig) {
        return CodeMirror.overlayMode(CodeMirror.getMode(config, parserConfig.backdrop || 'text/html'), CodeMirror.getMode(config, 'twig'))
      })
      this.codeMirror = CodeMirror.fromTextArea(this.$refs.txt, {
        autoRefresh: true,
        mode: 'htmltwig',
        theme: 'duotone-light',
        tabSize: 2,
        line: true,
        gutters: ['CodeMirror-linenumbers'],
        matchBrackets: true,
        showCursorWhenSelecting: true,
        styleActiveLine: true,
        lineNumbers: this.lineNumbers,
        styleSelectedText: true
      })

      this.codeMirror.setValue(this.innerValue || '')

      this.codeMirror.on('change', cm => {
        this.innerValue = cm.getValue()
      })
    },

    focus () {
      this.$refs.txt.focus()
    },

    refreshEditor (val) {
      this.codeMirror.setValue(val || '')
    }
  }
}

</script>
<style lang="postcss" scoped>
  .code-input-wrapper {
    width: 100%;

    &.transparent {
      >>> .CodeMirror {
        background-color: transparent !important;
      }
    }

    >>> .CodeMirror {
      background-color: theme(colors.input) !important;

      .CodeMirror-scroll {
        overflow: visible !important;
      }
    }
  }

  .code-input {
    border: 0;
    width: 100%;
    font-family: 'Mono', "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
  }
</style>
