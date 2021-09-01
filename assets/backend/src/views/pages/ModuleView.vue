<template>
  <div
    v-if="module"
    class="villain-component">
    <div class="villain-builder-wrapper">
      <div class="villain-builder-editor-wrapper">
        <codemirror
          ref="cmEditor"
          v-model="module.code"
          :options="codeOptions" />
      </div>

      <KModal
        v-if="showCreateRef"
        ref="createRefModal"
        v-shortkey="['esc', 'enter']"
        wide
        ok-text="OK"
        @shortkey.native="closeCreateRefModal"
        @ok="closeCreateRefModal">
        <template #header>
          Create ref
        </template>
        <KInput
          v-model="refName"
          name="newRef[name]"
          label="Ref name"
          help-text="i.e. `image`" />

        <div
          v-show="refName"
          class="villain-builder-block-picker">
          <div

            class="villain-builder-block-picker-available">
            <div
              v-for="b in availableBlocks"
              :key="b.name"
              class="villain-editor-plus-available-block"
              @mouseover="setHover(b.name)"
              @click="addBlock(b)">
              <div>
                <i
                  :class="b.icon"
                  class="fa fa-fw" />
              </div>
            </div>
          </div>
          <div
            class="villain-builder-block-picker-header">
            &rarr; {{ hoveredBlock }}
          </div>
        </div>
      </KModal>

      <KModal
        v-if="showRef"
        ref="refModal"
        v-shortkey="['esc', 'enter']"
        wide
        ok-text="OK"
        @shortkey.native="closeRefModal"
        @ok="closeRefModal">
        <template #header>
          Edit ref — {{ refName }}
        </template>
        <codemirror
          ref="refEditor"
          :options="refOptions" />
      </KModal>

      <KModal
        v-if="showVar"
        ref="varModal"
        v-shortkey="['esc', 'enter']"
        wide
        ok-text="OK"
        @shortkey.native="closeVarModal"
        @ok="closeVarModal">
        <template #header>
          Edit var — {{ varName }}
        </template>

        <codemirror
          ref="varEditor"
          :options="refOptions" />
      </KModal>

      <KModal
        v-if="showWrapper"
        ref="wrapperModal"
        v-shortkey="['esc', 'enter']"
        wide
        ok-text="OK"
        @shortkey.native="closeWrapperModal"
        @ok="closeWrapperModal">
        <template #header>
          Edit wrapper
        </template>
        <codemirror
          ref="wrapperEditor"
          v-model="module.wrapper"
          :options="codeOptions" />
      </KModal>

      <KModal
        v-if="showSVG"
        ref="SVGModal"
        v-shortkey="['esc', 'enter']"
        wide
        ok-text="OK"
        @shortkey.native="closeSVGModal"
        @ok="closeSVGModal">
        <template #header>
          Edit SVG
        </template>
        <codemirror
          ref="svgEditor"
          v-model="module.svg"
          :options="codeOptions" />
      </KModal>

      <div class="villain-builder-sidebar">
        <div class="inner">
          <div class="form">
            <ButtonSecondary
              v-shortkey="['meta', 's']"
              style="margin-bottom: 40px;"
              @shortkey="saveModule"
              @click="saveModule">
              Save
            </ButtonSecondary>

            <KInput
              v-model="module.name"
              name="module[name]"
              label="Name" />

            <KInput
              v-model="module.namespace"
              name="module[namespace]"
              label="Namespace" />

            <KInput
              v-model="module.helpText"
              name="module[helpText]"
              label="Help Text" />

            <KInput
              v-model="module.class"
              name="module[class]"
              label="Class" />

            <KInputCheckbox
              v-model="module.multi"
              name="module[multi]"
              label="Multi" />

            <div class="button-group">
              <ButtonSecondary
                full-width
                @click="showWrapper = true">
                Wrapper <FontAwesomeIcon
                  v-if="module.wrapper"
                  size="xs"
                  icon="check-circle" />
              </ButtonSecondary>
              <ButtonSecondary
                full-width
                @click="showSVG = true">
                SVG <FontAwesomeIcon
                  v-if="module.svg"
                  size="xs"
                  icon="check-circle" />
              </ButtonSecondary>
            </div>
          </div>
          <div class="refs">
            <h2>
              <div class="header-spread">
                REFs <span class="circle small">{{ module.refs.length }}</span>
              </div>
              <CircleButton
                @click.native.stop.prevent="showCreateRef = true">
                <FontAwesomeIcon icon="plus" />
              </CircleButton>
            </h2>
            <ul>
              <li
                v-for="ref in module.refs"
                :key="ref.name"
                class="text-mono padded">
                <span @click="selectRef(ref)">{{ ref.data.type }} - %{<strong>{{ ref.name }}</strong>}</span>
                <ButtonTiny @click="delRef(ref)">
                  Delete
                </ButtonTiny>
              </li>
            </ul>
          </div>

          <div class="vars">
            <h2>
              <div class="header-spread">
                VARs <span class="circle small">{{ Object.keys(module.vars).length || "0" }}</span>
              </div>
              <CircleButton @click.native.stop.prevent="createVar()">
                <FontAwesomeIcon icon="plus" />
              </CircleButton>
            </h2>
            <ul>
              <li
                v-for="(val, variable) in module.vars"
                :key="variable"
                class="text-mono padded">
                <div
                  @click="selectVar(variable)">
                  <span v-html="'{{ '" /><strong>{{ variable }}</strong> <span v-html="' }}'" />
                </div>
                <ButtonTiny @click="delVar(variable)">
                  Slett
                </ButtonTiny>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import gql from 'graphql-tag'
import CodeMirror from 'codemirror'
import '@128technology/codemirror-liquid-mode/liquid.css'
import { codemirror } from 'vue-codemirror'
import 'codemirror/lib/codemirror.css'
import 'codemirror/addon/mode/overlay'
import 'codemirror/mode/twig/twig.js'
import 'codemirror/mode/javascript/javascript.js'
import 'codemirror/mode/htmlmixed/htmlmixed.js'

import GET_MODULE from '../../gql/pages/MODULE_QUERY.graphql'
import STANDARD_BLOCKS from '../../components/villain/config/standardBlocks'
import STANDARD_VARS from '../../components/villain/config/standardVars'

CodeMirror.defineMode('htmltwig', function (config, parserConfig) {
  return CodeMirror.overlayMode(CodeMirror.getMode(config, parserConfig.backdrop || 'text/html'), CodeMirror.getMode(config, 'twig'))
})

export default {
  components: {
    codemirror
  },

  props: {
    moduleId: {
      type: Number,
      required: true
    }
  },

  data () {
    return {
      codeOptions: {
        tabSize: 4,
        indentUnit: 4,
        mode: 'htmltwig',
        lineNumbers: true,
        line: true
      },
      refOptions: {
        tabSize: 4,
        indentUnit: 4,
        mode: 'javascript',
        lineNumbers: true,
        line: true
      },
      newRef: {
        name: null,
        type: null
      },
      hoveredBlock: 'Velg blokk',
      showBlockPicker: false,
      showNamer: false,
      showWrapper: false,
      showSVG: false,
      showCreateRef: false,
      showRef: false,
      showVar: false,
      showModuleAttrs: false,
      codeMirror: null,
      refMirror: null,
      varMirror: null,
      refName: '',
      varName: '',
      currentRef: null,
      currentVar: null,
      prevRefName: null,
      prevVarName: null,
      modules: [],
      moduleSequence: [],
      namespaceOpen: [],
      selectedModulesForExport: []
    }
  },

  computed: {
    availableBlocks () {
      return STANDARD_BLOCKS[this.$i18n.locale]
    }
  },

  methods: {
    toggleSelectedModuleForExport (cls) {
      if (this.selectedModulesForExport.includes(cls)) {
        this.selectedModulesForExport = this.selectedModulesForExport.filter(t => t !== cls)
      } else {
        this.selectedModulesForExport.push(cls)
      }
    },

    getToken () {
      return localStorage.getItem('token')
    },

    isSelected (t) {
      return t === this.module
    },

    dropSvg (e) {
      if (e.dataTransfer.files.length > 1) {
        this.$alerts.alertError('Feil', 'Slipp kun én fil her.')
        return
      }

      const f = e.dataTransfer.files[0]

      if (f.type !== 'image/svg+xml') {
        this.$alerts.alertError('Feil', 'Kun SVG-fil tillatt')
        return
      }

      const reader = new FileReader()

      reader.onload = event => {
        this.module.svg = event.target.result
      }

      reader.readAsText(f)
    },

    createVar () {
      // TODO: Prompt for variable TYPE!
      this.$alerts.alertPrompt('Variable key', ({ data }) => {
        if (data) {
          if (!Object.prototype.hasOwnProperty.call(this.module, 'vars')) {
            this.module = {
              ...this.module,
              vars: {}
            }
          }
          const v = {
            type: 'text',
            value: 'Default value',
            label: 'Field name'
          }

          this.currentVar = v
          this.currentVarName = data

          this.module = {
            ...this.module,
            vars: {
              ...this.module.vars,
              [data]: v
            }
          }
        }
      })
    },

    setHover (name) {
      this.hoveredBlock = name
    },

    async closeRefModal () {
      this.saveRef()
      await this.$refs.refModal.close()
      this.showRef = false
    },

    async closeCreateRefModal () {
      await this.$refs.createRefModal.close()
      this.showCreateRef = false
      this.refName = ''
    },

    async closeVarModal () {
      this.saveVar()
      await this.$refs.varModal.close()
      this.showVar = false
    },

    async closeWrapperModal () {
      await this.$refs.wrapperModal.close()
      this.showWrapper = false
    },

    async closeSVGModal () {
      await this.$refs.SVGModal.close()
      this.showSVG = false
    },

    saveRef () {
      // get this ref
      const newRef = JSON.parse(this.$refs.refEditor.codemirror.getValue())
      // find ref to replace
      const oldRef = this.module.refs.find(r => r.name === this.prevRefName)
      if (oldRef) {
        const idx = this.module.refs.indexOf(oldRef)
        if (idx >= 0) {
          this.module.refs = [
            ...this.module.refs.slice(0, idx),
            newRef,
            ...this.module.refs.slice(idx + 1)
          ]
          this.resetRef()
        }
      }
    },

    delRef (ref) {
      const idx = this.module.refs.indexOf(ref)
      if (idx >= 0) {
        this.module.refs = [
          ...this.module.refs.slice(0, idx),
          ...this.module.refs.slice(idx + 1)
        ]
        this.resetRef()
      }
    },

    delVar (v) {
      this.$delete(this.module.vars, v)
    },

    saveVar () {
      // get this ref
      const newVar = JSON.parse(this.$refs.varEditor.codemirror.getValue())
      // find ref to replace
      const oldVar = this.module.vars[this.currentVarName]
      if (oldVar) {
        this.module = {
          ...this.module,
          vars: {
            ...this.module.vars,
            [this.currentVarName]: newVar
          }
        }
        this.resetVar()
      } else {
        console.error('==> Villain/builder/saveVar — var not found', this.currentVarName, this.module.vars)
      }
    },

    resetVar () {
      this.currentVar = {}
      this.currentVarName = ''
      this.prevVarName = null
      this.$refs.varEditor.codemirror.setValue('')
    },

    resetRef () {
      this.currentRef = {}
      this.prevRefName = null
    },

    addBlock (b) {
      const ref = {
        name: this.refName,
        data: { type: b.component.toLowerCase(), data: b.dataTemplate },
        description: ''
      }

      this.module.refs.push(ref)
      this.closeCreateRefModal()
    },

    selectModule (t) {
      this.resetRef()
      this.module = t
      this.codeMirror.setValue(this.module.code)
      this.codeMirror.refresh()
    },

    selectRef (r) {
      this.showRef = true

      this.$nextTick(() => {
        this.currentRef = { ...r }
        this.prevRefName = this.currentRef.name

        this.$refs.refEditor.codemirror.setValue(JSON.stringify(this.currentRef, null, 4))
        this.$refs.refEditor.codemirror.refresh()
      })
    },

    selectVar (v) {
      this.showVar = true

      this.$nextTick(() => {
        this.currentVar = v
        this.prevVarName = this.currentVar
        this.currentVarName = this.currentVar

        this.$refs.varEditor.codemirror.setValue(JSON.stringify(this.module.vars[this.currentVar], null, 4))
        this.$refs.varEditor.codemirror.refresh()
      })
    },

    async saveModule () {
      const moduleParams = {
        ...this.module,
        vars: JSON.stringify(this.module.vars),
        refs: JSON.stringify(this.module.refs)
      }

      delete moduleParams.id
      delete moduleParams.__typename

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateModule($moduleId: ID!, $moduleParams: ModuleParams!) {
              updateModule(moduleId: $moduleId, moduleParams: $moduleParams) {
                id
              }
            }
          `,
          variables: {
            moduleId: this.module.id,
            moduleParams
          },

          update: (store, { data: { updateModule } }) => {
            this.$router.push({ name: 'modules' })
          }
        })

        this.$toast.success({ message: this.$t('module.saved') })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    module: {
      query: GET_MODULE,
      variables () {
        return {
          moduleId: this.moduleId
        }
      },

      result ({ data: { module } }) {
        setTimeout(() => {
          this.$refs.cmEditor.codemirror.setSize('100%', '100%')
        }, 500)
      },

      fetchPolicy: 'no-cache',
      skip () {
        return !this.moduleId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
>>> .CodeMirror {
  height: auto;
  font-size: 15px;
}

.villain-component {
  @space padding-top 50px;
  @space! padding-right 20px;
}

.mb-2 {
  margin-bottom: 15px;
}

.form {
  button {
    width: 100%;
  }
}

.villain-builder-wrapper {
  display: flex;
  min-width: 0;
  height: 100%;

  .text-mono {
    font-family: "SF Mono", "Menlo", "Monaco", "Inconsolata", "Fira Mono", "Droid Sans Mono", "Source Code Pro", monospace;
  }

  .villain-builder-editor-wrapper {
    flex-grow: 1;
    min-width: 0;
    height: 100%;
  }

  .villain-builder-sidebar {
    padding-left: 20px;
    border-left: 1px solid;
    width: 350px;
    min-width: 0;

    .inner {
      @space padding 0.5rem;

      .refs, .vars {
        h2 {
          font-size: 16px;
          display: flex;
          width: 100%;
          justify-content: space-between;
          align-items: center;
          border-bottom: 1px solid #00000011;
          padding-bottom: 10px;
          padding-top: 5px;

          > div {
            display: flex;
            align-items: center;

            span {
              margin-left: 10px;
            }
          }
        }
      }
    }
  }

  ul {
    margin: 0;
    padding: 0;

    li {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 14px;
      cursor: pointer;
      list-style-type: none;
    }
  }

  .padded {
    padding-top: 15px;
    padding-bottom: 15px;
  }

  .villain-builder-block-attributes {
    display: flex;
    flex-direction: row;
    align-items: center;
    width: 100%;
    margin-right: 1rem;

    label {
      font-size: 80%;
      margin-bottom: 0;
      margin-right: 1rem;
    }
    input {
      font-size: 80%;
      width: 135px;
      margin-right: 1rem;

      &:nth-of-type(3) {
        width: 80px;
      }

      &:nth-of-type(4) {
        width: 100%;
        margin-right: 0;
      }
    }
  }
}

.button-group {
  @space margin-bottom 40px;
  display: flex;

  .btn {
    + .btn {
      margin-left: -1px;
    }
  }
}

.villain-builder-block-picker {
  .villain-builder-block-picker-available {
    display: flex;
    align-items: center;
  }

  .villain-builder-block-picker-header {
    align-self: center;
    font-size: 80%;
    margin-top: 25px;
  }

  .villain-editor-plus-available-block {
    cursor: pointer;
    border: 1px solid;
    padding: 8px 7px 4px;
    border-radius: 50%;
    margin-right: 5px;
  }
}

.villain-builder-editor-wrapper {
  .villain-builder-editor {
    width: 100%;
    height: 100%;
    position: relative;
  }
}

.villain-builder-refs {
  .villain-builder-ref {
    width: 100%;
    height: 100%;
    position: relative;
  }
}

.btn-negative {
  @color fg peach;
  border: 1px solid theme(colors.peach);
  border: 1px solid #0047FF;
  margin-top: 15px;
  background-color: transparent;
  display: block;
  width: 100%;
  padding: 15px;
}
</style>
<i18n>
  {
    "en": {
        "module.saved": "Module saved"
    },
    "no": {
        "module.saved": "Modul lagret"
    }
  }
</i18n>