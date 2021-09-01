<template>
  <div class="module-config">
    <div class="action-wrapper">
      <ButtonTiny
        right
        @click="showConfig = true">
        {{ $t('module-config') }}
      </ButtonTiny>
      <KModal
        v-if="showConfig"
        ref="modal"
        ok-text="OK"
        @ok="closeConfig">
        <template #header>
          {{ $t('module-config') }}
        </template>
        <div class="panes">
          <div>
            <h4>{{ $t('block-variables') }}</h4>

            <div
              v-for="(v, key) in vars"
              :key="key">
              <div class="field-wrapper">
                <template v-if="localVars[key].type === 'text'">
                  <KInput
                    v-model="localVars[key].value"
                    :name="`vars[${key}]`"
                    :label="v.label" />
                </template>
                <template v-if="localVars[key].type === 'string'">
                  <KInput
                    v-model="localVars[key].value"
                    :name="`vars[${key}]`"
                    :label="v.label" />
                </template>
                <template v-else-if="localVars[key].type === 'boolean'">
                  <KInputToggle
                    v-model="localVars[key].value"
                    :name="`vars[${key}]`"
                    :label="v.label" />
                </template>
                <template v-else-if="localVars[key].type === 'table'">
                  TABLE!
                </template>
              </div>
            </div>

            <button
              class="btn-secondary"
              type="button"
              @click.prevent="refetchVars">
              {{ $t('fetch-original-variables') }}
            </button>
          </div>

          <div>
            <h4>{{ $t('refered-blocks') }} [{{ refs.length }}]</h4>
            <div class="form-group">
              <button
                v-for="(ref, idx) in refs"
                :key="idx"
                type="button"
                class="btn-secondary"
                @click="replaceRefWithSource(ref)">
                {{ ref.name }} — {{ $t('replace-with-ref') }}
              </button>
            </div>
          </div>
        </div>
        <div class="panes mt-2">
          <div v-if="deletedBlocks.length">
            <h4>{{ $t('deleted-blocks') }} [{{ deletedBlocks.length }}]</h4>
            <button
              v-for="(b, idx) in deletedBlocks"
              :key="idx"
              type="button"
              class="btn-secondary"
              @click="undelete(b)">
              {{ b.name }} — {{ $t('restore') }}
            </button>
          </div>
        </div>
      </KModal>
    </div>
  </div>
</template>
<script>
import cloneDeep from 'lodash/cloneDeep'

export default {

  inject: [
    'available'
  ],
  props: {
    entryId: {
      type: String,
      required: false,
      default: null
    },

    moduleId: {
      type: [Number, String],
      required: true
    },
    refs: {
      type: Array,
      required: true
    },
    vars: {
      type: Object,
      required: true
    }
  },

  data () {
    return {
      showConfig: false,
      localVars: []
    }
  },

  computed: {
    deletedBlocks () {
      return this.refs.filter(r => r.deleted)
    }
  },

  mounted () {
    this.setLocalVars()
  },

  methods: {
    setLocalVars (vars = null) {
      if (vars) {
        this.localVars = cloneDeep(vars)
      } else {
        this.localVars = cloneDeep(this.vars)
      }
    },

    updateVars () {
      this.$emit('updateVars', { entryId: this.entryId, newVars: this.localVars })
    },

    refetchVars () {
      const foundModule = this.available.modules.find(t => parseInt(t.data.id) === parseInt(this.moduleId))
      const newVars = foundModule.data.vars
      this.$emit('updateVars', { newVars: newVars, entryId: this.entryId })
      this.setLocalVars(newVars)
    },

    replaceRefWithSource (ref) {
      const foundModule = this.available.modules.find(t => t.data.id === this.moduleId)
      const foundRef = foundModule.data.refs.find(r => r.name === ref.name)

      // replace our ref with foundRef
      const refIdx = this.refs.indexOf(ref)

      const newRefs = [
        ...this.refs.slice(0, refIdx),
        foundRef,
        ...this.refs.slice(refIdx + 1)
      ]

      this.$emit('updateRefs', { newRefs, entryId: this.entryId })
    },

    undelete (ref) {
      const refIdx = this.refs.indexOf(ref)
      delete ref.deleted

      const newRefs = [
        ...this.refs.slice(0, refIdx),
        ref,
        ...this.refs.slice(refIdx + 1)
      ]

      this.$emit('updateRefs', { newRefs, entryId: this.entryId })
    },

    closeConfig () {
      this.$refs.modal.close().then(() => {
        this.$nextTick(() => {
          this.updateVars()
          this.showConfig = false
        })
      })
    }
  }
}
</script>
<style lang="postcss" scoped>
  h4 {
    margin-bottom: 25px;
    font-weight: 400;
  }

  .field-wrapper {
    width: 100%;
    margin-bottom: 40px;

    input[type="text"] {
      padding-top: 12px;
      padding-bottom: 12px;
      padding-left: 15px;
      padding-right: 15px;
      width: 100%;
      background-color: #FAEFEA;
      border: 0;
      font-size: 17px;
    }

    .label-wrapper {
      display: flex;
      justify-content: space-between;
      margin-bottom: 4px;

      > span {
        font-size: 16px;
      }

      label {
        font-weight: 500;

        &:before {
          transition: opacity 0.5s ease;
          content: '';
          opacity: 0;
          position: absolute;
          top: 1px;
          width: 13px;
          height: 13px;
          margin-top: 3px;
          background-image: url("data:image/svg+xml,%3Csvg width='13' height='13' viewBox='0 0 13 13' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Ccircle cx='6.5' cy='6.5' r='6.5' fill='%23FF0000'/%3E%3C/svg%3E%0A");
        }

        span {
          transition: padding-left 500ms ease;
          transition-delay: 0.25s;
          padding-left: 0;
        }

        &.failed {
          position: relative;
          &:before {
            transition: opacity 0.5s ease;
            transition-delay: 0.25s;
            opacity: 1;
          }

          span {
            transition: padding-left 500ms ease;
            padding-left: 30px;
          }
        }
      }
    }

    .meta {
      display: flex;
      justify-content: space-between;
      margin-top: 10px;
    }
  }
</style>
<i18n>
  {
    "en": {
      "module-config": "Module config",
      "block-variables": "Block variables",
      "fetch-original-variables": "Fetch original variables",
      "fetch-missing-refs": "Fetch missing refs",
      "refered-blocks": "Refered blocks",
      "replace-with-ref": "Replace with ref",
      "deleted-blocks": "Deleted blocks",
      "restore": "Restore"
    },
    "no": {
      "module-config": "Moduloppsett",
      "block-variables": "Blokkvariabler",
      "fetch-original-variables": "Hent orginale variabler",
      "fetch-missing-refs": "Hent manglende blokker",
      "refered-blocks": "Refererte blokker",
      "replace-with-ref": "Erstatt med referanseblokk",
      "deleted-blocks": "Slettede blokker",
      "restore": "Gjenopprett"

    }
  }
</i18n>
