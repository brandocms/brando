<template>
  <div
    id="file-input"
    ref="container"
    class="file-input">
    <div
      v-if="!supportsUpload"
      v-html="strings.upload" />
    <div>
      <button
        v-if="!fileSelected && !existingFile"
        :class="buttonClass"
        class="ml-2"
        @click.prevent="selectFile">
        {{ strings.select }}
      </button>
      <div
        v-if="!fileSelected && existingFile"
        class="ml-2">
        <small>
          <i class="fa fa-file mr-2" /> <strong>{{ existingFile }}</strong>
        </small>
        <br>
        <button
          :class="buttonClass"
          class="mt-2"
          @click.prevent="selectFile">
          {{ strings.change }}
        </button>
      </div>
      <div
        v-else
        class="ml-2">
        <template v-if="fileName">
          <small>
            <i class="fa fa-file mr-2" /> <strong>{{ fileName }}</strong> - {{ fileSize }}
          </small>
          <br>
          <button
            :class="buttonClass"
            class="mt-2"
            @click.prevent="selectFile">
            {{ strings.change }}
          </button>
        </template>
        <button
          v-if="removable"
          :class="removeButtonClass"
          @click.prevent="removeFile">
          {{ strings.remove }}
        </button>
      </div>
    </div>
    <input
      :id="id"
      ref="fileInput"
      :name="name"
      type="file"
      style="display:none;"
      @change="onFileChange">
  </div>
</template>

<script>
export default {
  name: 'FileInput',
  props: {
    width: {
      type: [String, Number],
      default: Number.MAX_SAFE_INTEGER
    },
    height: {
      type: [String, Number],
      default: Number.MAX_SAFE_INTEGER
    },
    margin: {
      type: [String, Number],
      default: 0
    },
    size: {
      type: [String, Number],
      default: Number.MAX_SAFE_INTEGER
    },
    name: {
      type: String,
      default: null
    },
    id: {
      type: [String, Number],
      default: null
    },
    buttonClass: {
      type: String,
      default: 'btn btn-primary button'
    },
    removeButtonClass: {
      type: String,
      default: 'btn btn-secondary button secondary'
    },
    aspectButtonClass: {
      type: String,
      default: 'btn btn-secondary button secondary'
    },
    prefill: {
      type: [String, File],
      default: ''
    },
    prefillOptions: {
      type: Object,
      default: () => {
        return {}
      }
    },
    crop: {
      type: Boolean,
      default: true
    },
    radius: {
      type: [String, Number],
      default: 0
    },
    removable: {
      type: Boolean,
      default: false
    },
    autoToggleAspectRatio: {
      type: Boolean,
      default: false
    },
    toggleAspectRatio: {
      type: Boolean,
      default: false
    },
    changeOnClick: {
      type: Boolean,
      default: true
    },
    plain: {
      type: Boolean,
      default: false
    },
    zIndex: {
      type: Number,
      default: 10000
    },
    customStrings: {
      type: Object,
      default: () => {
        return {}
      }
    }
  },

  data () {
    return {
      fileName: '',
      fileSize: '',
      existingFile: null,
      fileSelected: false,
      draggingOver: false,
      strings: {
        upload: '<p>Your device does not support file uploading.</p>',
        drag: 'Drag an image or <br>click here to select a file',
        tap: 'Tap here to select a file <br>from your gallery',
        change: 'Change file',
        aspect: 'Landscape/Portrait',
        remove: 'Remove file',
        select: 'Select a file',
        selected: '<p>File successfully selected!</p>',
        fileSize: 'The file size exceeds the limit',
        fileType: 'This file type is not supported.'
      }
    }
  },
  computed: {
    supportsUpload () {
      if (navigator.userAgent.match(/(Android (1.0|1.1|1.5|1.6|2.0|2.1))|(Windows Phone (OS 7|8.0))|(XBLWP)|(ZuneWP)|(w(eb)?OSBrowser)|(webOS)|(Kindle\/(1.0|2.0|2.5|3.0))/)) {
        return false
      }
      const el = document.createElement('input')
      el.type = 'file'
      return !el.disabled
    },
    supportsDragAndDrop () {
      const div = document.createElement('div')
      return (('draggable' in div) || ('ondragstart' in div && 'ondrop' in div)) && !('ontouchstart' in window || navigator.msMaxTouchPoints)
    },
    computedClasses () {
      const classObject = {}
      classObject['dragging-over'] = this.draggingOver
      return classObject
    },
    fontSize () {
      return Math.min(0.04 * this.previewWidth, 21) + 'px'
    }
  },
  mounted () {
    this.updateStrings()
    if (this.prefill) {
      this.existingFile = this.prefill
    }
  },

  methods: {
    updateStrings () {
      for (let s in this.customStrings) {
        if (s in this.strings && typeof this.customStrings[s] === 'string') {
          this.strings[s] = this.customStrings[s]
        }
      }
    },
    onClick () {
      if (!this.fileSelected) {
        this.selectFile()
        return
      }

      if (this.changeOnClick) {
        this.selectFile()
      }

      this.$emit('click')
    },
    onDragStart () {
      if (!this.supportsDragAndDrop) {
        return
      }
      this.draggingOver = true
    },
    onDragStop () {
      if (!this.supportsDragAndDrop) {
        return
      }
      this.draggingOver = false
    },
    onFileDrop (e) {
      this.onDragStop()
      this.onFileChange(e)
    },
    onFileChange (e) {
      let files = e.target.files || e.dataTransfer.files
      if (!files.length) {
        return
      }
      if (files[0].size <= 0 || files[0].size > this.size * 1024 * 1024) {
        alert(this.strings.fileSize + ' (' + this.size + 'MB)')
        return
      }
      if (files[0].name === this.fileName && files[0].size === this.fileSize && this.fileModified === files[0].lastModified) {
        return
      }

      this.file = files[0]
      this.fileName = files[0].name
      this.fileSize = files[0].size
      this.fileModified = files[0].lastModified
      this.fileType = files[0].type
      this.fileSelected = true
      this.image = ''
      this.$emit('change')
    },
    selectFile () {
      this.$refs.fileInput.click()
    },
    removeFile () {
      this.$refs.fileInput.value = ''
      this.$refs.fileInput.type = ''
      this.$refs.fileInput.type = 'file'
      this.fileName = ''
      this.fileType = ''
      this.fileSize = 0
      this.fileModified = 0
      this.fileSelected = false
      this.file = null
      this.imageObject = null
      this.$emit('remove')
    }
  }
}
</script>
