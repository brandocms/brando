<!--
Drop images on this component.
After the files are dropped, the `transform` prop function is called on the files.
Then value is set to the transformed result
-->

<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :help-text="helpText"
    :value="value">
    <template #default>
    </template>
    <template #outsideValidator>
      <div v-if="innerValue">
        <div
          v-if="innerValue.length"
          class="entries">
          <slot name="head"></slot>
          <div
            v-for="entry in innerValue"
            :key="entry.thumb"
            class="entries__entry">
            <div class="entries__entry__content">
              <slot
                name="row"
                :entry="entry">
                {{ entry.id }}
              </slot>
            </div>
            <div class="entries__entry__actions">
              <ButtonPrimary
                :loading="loading"
                @click="save(entry, setLoader)">
                {{ $t('save') }}
              </ButtonPrimary>
              <ButtonSecondary
                class="ml-xs"
                @click="removeEntry(entry)">
                {{ $t('remove') }}
              </ButtonSecondary>
            </div>
          </div>
        </div>
      </div>

      <div>
        <div
          class="dropzone">
          <div class="upload">
            <div
              v-if="!files.length"
              class="droparea">
              <div class="text-center">
                {{ $t('drop-files-here-to-upload') }}<br>
                <span class="file-selector-button">
                  {{ $t('pick-files') }}
                  <label for="image"></label>
                  <input
                    id="image"
                    type="file"
                    name="image"
                    accept="image/*"
                    multiple="multiple"
                    @change="change" />
                </span><br>
                <div class="size-limit">
                  {{ $t('max-filesize', { sizeLimit: sizeLimit }) }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </KFieldBase>
</template>

<script>
export default {

  inject: [
    'adminChannel'
  ],
  props: {
    value: {
      type: Array,
      default: () => []
    },

    transform: {
      type: Function,
      required: true
    },

    save: {
      type: Function,
      required: true
    },

    showDelete: {
      type: Boolean,
      default: true
    },

    showUpload: {
      type: Boolean,
      default: true
    },

    helpText: {
      type: String,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: true
    },

    name: {
      type: String,
      required: true
    },

    sizeLimit: {
      type: Number,
      default: 3
    }
  },

  data () {
    return {
      new: false,
      files: [],
      config: {},
      edit: false,
      editObject: null,
      loading: false
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

  watch: {
    files (val) {
      if (val && val.length) {
        this.innerValue.images = []
        val.forEach((v, idx) => {
          this.innerValue.images.push({
            image: v.file,
            sequence: idx
          })
        })
        this.innerValue = this.transform(val)
      } else {
        this.innerValue.images = []
      }
    }
  },

  created () {
    if (this.value) {
      this.new = false
      this.innerValue = this.value
    } else {
      this.new = true
      this.innerValue = []
    }
  },

  mounted () {
    this.watchDrop(this.$el)
  },

  methods: {
    setLoader (value) {
      this.loading = value
    },

    getKey (e) {
      return Math.random().toString(36).substr(2, 10) + Math.random().toString(36).substr(2, 10)
    },

    watchDrop (el) {
      if (this.dropElement) {
        try {
          document.removeEventListener('dragenter', this.onDragenter, false)
          document.removeEventListener('dragleave', this.onDragleave, false)
          document.removeEventListener('drop', this.onDocumentDrop, false)
          this.dropElement.removeEventListener('dragover', this.onDragover, false)
          this.dropElement.removeEventListener('drop', this.onDrop, false)
        } catch (e) {
        }
      }

      this.dropElement = el

      if (this.dropElement) {
        document.addEventListener('dragenter', this.onDragenter, false)
        document.addEventListener('dragleave', this.onDragleave, false)
        document.addEventListener('drop', this.onDocumentDrop, false)
        this.dropElement.addEventListener('dragover', this.onDragover, false)
        this.dropElement.addEventListener('drop', this.onDrop, false)
      }
    },

    addDataTransfer (dataTransfer) {
      const files = []
      if (dataTransfer.items && dataTransfer.items.length) {
        const items = []
        for (let i = 0; i < dataTransfer.items.length; i++) {
          let item = dataTransfer.items[i]
          if (item.getAsEntry) {
            item = item.getAsEntry() || item.getAsFile()
          } else if (item.webkitGetAsEntry) {
            item = item.webkitGetAsEntry() || item.getAsFile()
          } else {
            item = item.getAsFile()
          }
          if (item) {
            items.push(item)
          }
        }
        return new Promise((resolve, reject) => {
          const forEach = (i) => {
            const item = items[i]
            if (!item || (this.maximum > 0 && files.length >= this.maximum)) {
              return resolve(this.add(files))
            }
            this.getEntry(item).then(function (results) {
              files.push(...results)
              forEach(i + 1)
            })
          }
          forEach(0)
        })
      }
      if (dataTransfer.files.length) {
        for (let i = 0; i < dataTransfer.files.length; i++) {
          files.push(dataTransfer.files[i])
          if (this.maximum > 0 && files.length >= this.maximum) {
            break
          }
        }
        return Promise.resolve(this.add(files))
      }
      return Promise.resolve([])
    },

    getEntry (entry, path = '') {
      return new Promise((resolve, reject) => {
        if (entry.isFile) {
          entry.file(function (file) {
            resolve([
              {
                size: file.size,
                name: path + file.name,
                type: file.type,
                file
              }
            ])
          })
        } else {
          resolve([])
        }
      })
    },

    onDragenter (e) {
      e.preventDefault()
      if (this.dropActive) {
        return
      }
      if (!e.dataTransfer) {
        return
      }
      const dt = e.dataTransfer
      if (dt.files && dt.files.length) {
        this.dropActive = true
      } else if (!dt.types) {
        this.dropActive = true
      } else if (dt.types.indexOf && dt.types.indexOf('Files') !== -1) {
        this.dropActive = true
      } else if (dt.types.contains && dt.types.contains('Files')) {
        this.dropActive = true
      }
    },

    editEntry (entry) {
      this.editObject = entry
      this.edit = true
    },

    removeEntry (entry) {
      const e = this.innerValue.find(e => e.id === entry.id)
      const idx = this.innerValue.indexOf(e)
      this.innerValue = [
        ...this.innerValue.slice(0, idx),
        ...this.innerValue.slice(idx + 1)
      ]
    },

    onDragleave (e) {
      e.preventDefault()
      if (!this.dropActive) {
        return
      }
      if (e.target.nodeName === 'HTML' || e.target === e.explicitOriginalTarget || (!e.fromElement && (e.clientX <= 0 || e.clientY <= 0 || e.clientX >= window.innerWidth || e.clientY >= window.innerHeight))) {
        this.dropActive = false
      }
    },

    onDragover (e) {
      e.preventDefault()
    },

    onDocumentDrop () {
      this.dropActive = false
    },

    onDrop (e) {
      e.preventDefault()
      this.addDataTransfer(e.dataTransfer)
    },

    clearFiles () {
      this.files = []
    },

    change (e) {
      this.addInputFile(e.target)
      if (e.target.files) {
        e.target.value = ''
        if (e.target.files.length && !/safari/i.test(navigator.userAgent)) {
          e.target.type = ''
          e.target.type = 'file'
        }
      } else {
        // ie9 fix #219
        this.$destroy()
        // eslint-disable-next-line
        new this.constructor({
          el: this.$el
        })
      }
    },

    add (srcFiles) {
      const files = []
      if (srcFiles) {
        for (let i = 0; i < srcFiles.length; i++) {
          let blob
          let thumb
          const file = srcFiles[i]
          let actualFile

          if (file.file instanceof Blob) {
            blob = window.URL.createObjectURL(file.file)
            thumb = (blob && file.type.substr(0, 6) === 'image/') ? blob : null
            actualFile = file.file
          } else {
            window.URL = window.URL || window.webkitURL
            if (window.URL && window.URL.createObjectURL) {
              blob = window.URL.createObjectURL(file)
              thumb = (blob && file.type.substr(0, 6) === 'image/') ? blob : null
            }
            actualFile = file
          }

          const newFile = {
            active: false,
            success: false,
            error: false,
            id: Math.random().toString(36).substr(2),
            size: file.size,
            name: file.webkitRelativePath || file.relativePath || file.name,
            type: file.type,
            blob,
            thumb,
            file: actualFile
          }

          if (newFile.size > this.sizeLimit * 1024 * 1024) {
            const errorMsg = `
              ${newFile.name}<br><br>
              Filen du vil laste opp er for stor. <br><br>
              Maks tillatt størrelse for feltet er <br><br>
              &lt;&lt; ${this.sizeLimit}MB. &gt;&gt;<br><br>
              Du kan komprimere filen før du laster den opp med en online tjeneste
              som <a href="https://squoosh.app/" target="_blank" rel="noopener nofollow">squoosh.app</a> eller en mac-applikasjon
              som f.eks <a href="https://imageoptim.com/mac/" target="_blank" rel="noopener nofollow">ImageOptim</a>.`
            this.$alerts.alertError('OBS!', errorMsg)
          } else {
            files.push(newFile)
          }
        }
      }

      this.files = files
    },

    addInputFile (el) {
      const srcFiles = el.files
      this.add(srcFiles)
    }
  }
}
</script>

<style lang="postcss" scoped>
.sort-container {
  display: flex;
  flex-wrap: wrap;
}

.image-wrapper {
  border: 5px solid #000;
  cursor: pointer;
  height: 125px;
  padding: 2px;
  position: relative;
  width: 125px;
  margin: 0.25rem;

  &.selected {
    background-color: theme(colors.blue);
    border: 5px solid theme(colors.blue);
    padding: 0;

    img {
      opacity: 0.50;
    }
  }
}

.example-drag label.btn {
  margin-bottom: 0;
  margin-right: 0;
}

.example-drag .drop-active {
  top: 0;
  bottom: 0;
  right: 0;
  left: 0;
  position: fixed;
  z-index: 9999;
  opacity: .6;
  text-align: center;
  background: #000;
}

.example-drag .drop-active h3 {
  margin: -.5em 0 0;
  position: absolute;
  top: 50%;
  left: 0;
  right: 0;
  -webkit-transform: translateY(-50%);
  -ms-transform: translateY(-50%);
  transform: translateY(-50%);
  font-size: 40px;
  color: #fff;
  padding: 0;
}

.droparea {
  @space margin-bottom xs;
  background-color: theme(colors.peach);
  min-height: 320px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;

  div {
    @fontsize lg;
  }

  .size-limit {
    font-size: 15px;
    padding-top: 10px;
  }
}

.filesize {
  font-family: theme(typography.families.mono);
  @extend .fit;
  font-size: 14px;
  text-align: right;
}

.file-selector-button {
  @space margin-top sm;
  @color fg peach;
  @color bg blue;
  padding-top: 10px;
  border: 1px solid theme(colors.blue);
  height: 60px;
  border-radius: 30px;
  padding-bottom: 0px;
  min-width: 205px;
  text-align: center;
  transition: background-color 0.25s ease, border-color 0.25s ease;
  overflow: hidden;
  position: relative;
  text-align: center;
  display: inline-block;

  &:hover {
    @color fg peach;
    @color bg dark;
    border-color: theme(colors.dark);
  }
}

label {
  background: #fff;
  opacity: 0;
  font-size: 20em;
  z-index: 1;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  position: absolute;
  width: 100%;
  height: 100%;
}

input[type=file] {
  background: rgba(255,255,255,0);
  overflow: hidden;
  position: fixed;
  width: 1px;
  height: 1px;
  z-index: -1;
  opacity: 0;
}

.entries {
  width: 100%;

  .entries__entry {
    @space padding-y 25px;
    @space margin-bottom 25px;
    background-color: #fefcfb;
    border-bottom: 1px solid theme(colors.peachDarker);

    >>> .field-wrapper {
      margin-bottom: 22px;
    }
  }

  .entries__entry__actions {
    display: flex;
    background-color: #faefea;
    padding-top: 15px;
    padding-bottom: 15px;
    padding-left: 15px;
    padding-right: 15px;
  }
}

.button-bar {
  display: flex;
  justify-content: center;
}

.button-group {
  @space margin-top xs;
  display: flex;

  .btn {
    + .btn {
      margin-left: -1px;
    }
  }
}
</style>

<i18n>
  {
    "en": {
      "save": "Save",
      "edit": "Edit",
      "remove": "Remove",
      "no-connected-objects": "No connected objects",
      "remove-files": "Remove files",
      "drop-files-here-to-upload": "Drop files here to upload or",
      "pick-files": "Pick files",
      "max-filesize": "Maks filstørrelse er {sizeLimit}MB."
    },
    "no": {
      "save": "Lagre",
      "edit": "Endre",
      "remove": "Fjern",
      "no-connected-objects": "Ingen tilknyttede objekter",
      "remove-files": "Fjern filer",
      "drop-files-here-to-upload": "Slipp filene dine her for å laste opp eller",
      "pick-files": "Plukk filer"
    }
  }
</i18n>
