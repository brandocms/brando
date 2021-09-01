<template>
  <div
    ref="dropzone"
    class="dropzone">
    <div class="upload">
      <table
        v-show="files.length"
        class="table table-bordered text-sm hmm">
        <tr
          v-for="file in files"
          :key="file.id"
          :data-id="file.id">
          <td class="fit">
            <img
              v-if="file.thumb"
              :src="file.thumb"
              width="40"
              height="auto">
          </td>
          <td class="name">
            <span>{{ file.name }}</span>
          </td>
          <td class="fit filesize">
            {{ file.size | formatSize }}
          </td>
          <transition
            type="fade"
            mode="out-in">
            <td
              v-if="file.error"
              key="denied"
              class="fit">
              <i class="fal fa-fw fa-exclamation-circle text-danger" /> 404
            </td>
            <td
              v-else-if="file.success"
              key="success"
              class="status">
              <div class="check-icon-wrapper">
                <svg
                  id="Layer_1"
                  version="1.1"
                  preserveAspectRatio="xMidYMid meet"
                  viewBox="0 0 98.5 98.5"
                  enable-background="new 0 0 98.5 98.5"
                  xml:space="preserve">
                  <path
                    class="checkmark"
                    fill="none"
                    stroke-width="8"
                    stroke-miterlimit="10"
                    d="M81.7,17.8C73.5,9.3,62,4,49.2,4
                  C24.3,4,4,24.3,4,49.2s20.3,45.2,45.2,45.2s45.2-20.3,45.2-45.2c0-8.6-2.4-16.6-6.5-23.4l0,0L45.6,68.2L24.7,47.3" />
                </svg>
              </div>
            </td>
            <td
              v-else-if="file.active"
              key="active"
              class="status active">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="30"
                height="30"
                preserveAspectRatio="xMidYMid meet"
                viewBox="0 0 44 44"
                stroke="blue">
                <g
                  fill="none"
                  fill-rule="evenodd"
                  stroke-width="2">
                  <circle
                    cx="22"
                    cy="22"
                    r="19.6786">
                    <animate
                      attributeName="r"
                      begin="0s"
                      dur="1.8s"
                      values="1; 20"
                      calcMode="spline"
                      keyTimes="0; 1"
                      keySplines="0.165, 0.84, 0.44, 1"
                      repeatCount="indefinite" />
                    <animate
                      attributeName="stroke-opacity"
                      begin="0s"
                      dur="1.8s"
                      values="1; 0"
                      calcMode="spline"
                      keyTimes="0; 1"
                      keySplines="0.3, 0.61, 0.355, 1"
                      repeatCount="indefinite" />
                  </circle>
                  <circle
                    cx="22"
                    cy="22"
                    r="13.8461">
                    <animate
                      attributeName="r"
                      begin="-0.9s"
                      dur="1.8s"
                      values="1; 20"
                      calcMode="spline"
                      keyTimes="0; 1"
                      keySplines="0.165, 0.84, 0.44, 1"
                      repeatCount="indefinite" />
                    <animate
                      attributeName="stroke-opacity"
                      begin="-0.9s"
                      dur="1.8s"
                      values="1; 0"
                      calcMode="spline"
                      keyTimes="0; 1"
                      keySplines="0.3, 0.61, 0.355, 1"
                      repeatCount="indefinite" />
                  </circle>
                </g>
              </svg>
            </td>
            <td
              v-else
              key="other"
              class="status">
              —
            </td>
          </transition>
        </tr>
      </table>
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
              @change="change">
          </span>
        </div>
      </div>
      <div class="button-bar">
        <div class="button-group">
          <button
            v-if="!uploading"
            :disabled="!files.length"
            type="button"
            class="btn btn-primary"
            @click.prevent="upload">
            &uarr; {{ $t('start-upload') }}
          </button>
          <button
            type="button"
            class="btn btn-primary"
            @click.prevent="$emit('close')">
            <i
              class="fa fa-window-close"
              aria-hidden="true" />
            {{ $t('close-window') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import gql from 'graphql-tag'

export default {
  props: {
    imageSeriesId: {
      type: [Number, String],
      required: true
    }
  },

  data () {
    return {
      files: [],
      active: false,
      dropActive: false,
      uploading: 0
    }
  },

  mounted () {
    this.watchDrop(this.$el)
  },

  methods: {
    async upload () {
      for (let i = 0; i < this.files.length; i++) {
        this.uploading++
        this.files[i].active = true
        await this.uploadFile(this.files[i])
      }
    },

    uploadFile (file) {
      return new Promise((resolve, reject) => {
        const params = { image: file.file }
        this.$apollo.mutate({
          mutation: gql`
            mutation CreateImage($imageSeriesId: ID!, $imageUploadParams: ImageUpload) {
              createImage(
                imageSeriesId: $imageSeriesId,
                imageUploadParams: $imageUploadParams
              ) {
                id
                image {
                  path
                  credits
                  title
                  alt
                  focal
                  width
                  height
                  sizes
                  thumb: url(size: "thumb")
                  medium: url(size: "medium")
                }
                imageSeriesId
                sequence
                updatedAt
                deletedAt
              }
            }
          `,
          variables: {
            imageSeriesId: this.imageSeriesId,
            imageUploadParams: params
          },
          context: {
            fetchOptions: {
              onUploadProgress: progress => {
                console.info(progress)
              }
            }
          },

          update: (store, { data: { createImage } }) => {
            this.$emit('save', createImage)
          }
        }).then(() => {
          file.active = false
          file.success = true
          this.uploading--
          resolve()
        }).catch(e => {
          console.error(e)
          file.error = true
          file.active = false
          this.uploading--
          if (e.graphQLErrors) {
            resolve()
          }
        })
      })
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

          files.push(newFile)
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
    background-color: theme(colors.dark);
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

table {
  width: 100%;
  @fontsize sm;

  &.table-bordered {
    td {
      border: 1px solid #dee2e6;
      vertical-align: middle;
      padding: 0.75rem;
    }
  }

  tr {
    td {
      &:first-of-type {
        width: 65px;
      }

      &.status {
        width: 60px;
        height: 60px;
        max-height: 60px;
        margin: 0 auto;
        text-align: center;

        &.active {
          transform: scale(0.8);
        }
      }

      &.name {
        position: relative;
        background-color: transparent;

        span {
          position: relative;
          z-index: 2;
        }

        &:before {
          content: '';
          background-color: pink;
          position: absolute;
          top: 0;
          left: 0;
          height: 100%;
          width: 0%;
          z-index: 1;
        }
      }
    }
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

.check-icon-wrapper {
  width: 20px;
  margin: 0 auto;
  margin-left: 7px;

  .checkmark {
    stroke: theme(colors.blue);
    stroke-dashoffset: 745.74853515625;
    stroke-dasharray: 745.74853515625;
    animation: dash 2s ease-out forwards;
  }

  @keyframes dash {
    0% {
      stroke-dashoffset: 745.74853515625;
    }
    100% {
      stroke-dashoffset: 0;
    }
  }
}
</style>

<i18n>
  {
    "en": {
      "drop-files-here-to-upload": "Drop files here to upload or",
      "pick-files": "Select files",
      "start-upload": "Start upload",
      "close-window": "Close window"
    },
    "no": {
      "drop-files-here-to-upload": "Slipp filene dine her for å laste opp eller",
      "pick-files": "Velg filer",
      "start-upload": "Start opplasting",
      "close-window": "Lukk vindu"
    }
  }
</i18n>
