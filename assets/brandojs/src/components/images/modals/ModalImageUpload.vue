<template>
  <modal
    v-if="showModal"
    :chrome="false"
    :large="true"
    :show="showModal"
    @cancel="closeModal"
    @ok="closeModal">
    <div class="card mb-3">
      <div class="card-header text-center">
        <h5 class="section mb-0">
          Last opp bilder til {{ imageSeries.name }}
        </h5>
      </div>
      <div class="card-body">
        <div class="example-drag">
          <div class="upload">
            <table
              v-show="files.length"
              class="table table-bordered text-sm">
              <tr
                v-for="file in files"
                :key="file.id">
                <td class="fit">
                  <img
                    v-if="file.thumb"
                    :src="file.thumb"
                    width="40"
                    height="auto">
                </td>
                <td class="ws-normal">
                  {{ file.name }}
                </td>
                <td class="fit">
                  {{ file.size | formatSize }}
                </td>
                <transition
                  type="fade"
                  mode="out-in">
                  <td
                    v-if="file.error === 'denied'"
                    key="denied"
                    class="fit">
                    <i class="fal fa-fw fa-exclamation-circle text-danger" /> 404
                  </td>
                  <td
                    v-else-if="file.success"
                    key="success"
                    class="fit">
                    OK
                  </td>
                  <td
                    v-else-if="file.active"
                    key="active"
                    class="fit">
                    <svg xmlns="http://www.w3.org/2000/svg" width="44" height="44" viewBox="0 0 44 44" stroke="blue">
                      <g fill="none" fill-rule="evenodd" stroke-width="2">
                        <circle cx="22" cy="22" r="19.6786">
                          <animate attributeName="r" begin="0s" dur="1.8s" values="1; 20" calcMode="spline" keyTimes="0; 1" keySplines="0.165, 0.84, 0.44, 1" repeatCount="indefinite"/>
                          <animate attributeName="stroke-opacity" begin="0s" dur="1.8s" values="1; 0" calcMode="spline" keyTimes="0; 1" keySplines="0.3, 0.61, 0.355, 1" repeatCount="indefinite"/>
                        </circle>
                        <circle cx="22" cy="22" r="13.8461">
                          <animate attributeName="r" begin="-0.9s" dur="1.8s" values="1; 20" calcMode="spline" keyTimes="0; 1" keySplines="0.165, 0.84, 0.44, 1" repeatCount="indefinite"/>
                          <animate attributeName="stroke-opacity" begin="-0.9s" dur="1.8s" values="1; 0" calcMode="spline" keyTimes="0; 1" keySplines="0.3, 0.61, 0.355, 1" repeatCount="indefinite"/>
                        </circle>
                      </g>
                    </svg>
                  </td>
                  <td
                    v-else
                    key="other"
                    class="fit">
                    —
                  </td>
                </transition>
              </tr>
            </table>
            <div
              v-show="!files.length"
              class="upload-text-container">
              <div class="text-center">
                Slipp filene dine her for å laste opp eller<br>
                <FileUpload
                  ref="upload"
                  v-model="files"
                  :post-action="`/admin/api/images/upload/image_series/${imageSeries.id}`"
                  :headers="{'authorization': getToken()}"
                  :multiple="true"
                  :drop="true"
                  class="file-selector-button"
                  name="image"
                  accept="image/*"
                  @input-filter="inputFilter"
                  @input-file="inputFile">
                  Velg filer
                </FileUpload>
              </div>
            </div>
            <div class="button-bar">
              <div class="button-group">
                <button
                  v-if="!$refs.upload || !$refs.upload.active"
                  :disabled="!files.length"
                  type="button"
                  class="btn btn-primary"
                  @click.prevent="$refs.upload.active = true">
                  &uarr; Start opplasting
                </button>
                <button
                  v-else
                  type="button"
                  class="btn btn-primary"
                  @click.prevent="$refs.upload.active = false">
                  <i
                    class="fa fa-stop"
                    aria-hidden="true" />
                  Stopp opplasting
                </button>
                <button
                  :disabled="$refs.upload && $refs.upload.active"
                  type="button"
                  class="btn btn-primary"
                  @click.prevent="closeModal">
                  <i
                    class="fa fa-window-close"
                    aria-hidden="true" />
                  Lukk vindu
                </button>
              </div>
            </div>

            <div
              v-show="$refs.upload && $refs.upload.dropActive"
              class="drop-active">
              <h3>Slipp filene her for å laste opp</h3>
            </div>
          </div>
        </div>
      </div>
    </div>
  </modal>
</template>

<script>
import { mapActions } from 'vuex'
import Modal from '../../Modal.vue'
import gql from 'graphql-tag'

export default {
  components: {
    Modal
  },

  props: {
    showModal: {
      type: Boolean,
      default: false
    },

    imageSeries: {
      type: Object,
      required: true
    },

    uploadCallback: {
      type: Function,
      default: null
    }
  },

  data () {
    return {
      files: []
    }
  },

  methods: {
    closeModal () {
      this.files = []
      this.$emit('close')
    },

    getToken () {
      return `Bearer: ${this.token}`
    },

    inputFile (newFile, oldFile) {
      if (newFile && oldFile) {
        // Uploaded successfully
        if (newFile.success !== oldFile.success) {
          if (newFile.response.status === '200') {
            if (this.uploadCallback) {
              this.uploadCallback(newFile.response.image)
            } else {
              this.storeImage(newFile.response.image)
            }
          }
        }
        // Upload error
        if (newFile.error !== oldFile.error) {
          console.error('error', newFile.error, newFile)
        }
      }
    },

    inputFilter (newFile, oldFile, prevent) {
      if (newFile && (!oldFile || newFile.file !== oldFile.file)) {
        newFile.blob = ''
        let URL = window.URL || window.webkitURL
        if (URL && URL.createObjectURL) {
          newFile.blob = URL.createObjectURL(newFile.file)
        }
        newFile.thumb = ''
        if (newFile.blob && newFile.type.substr(0, 6) === 'image/') {
          newFile.thumb = newFile.blob
        }
      }
    },

    ...mapActions('images', [
      'storeImage'
    ])
  },

  apollo: {
    token: gql`
      query getToken {
        token @client
      }
    `
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

.upload-text-container {
  @space margin-bottom xs;
  background-color: theme(colors.peach);
  min-height: 320px;
  display: flex;
  align-items: center;
  justify-content: center;

  div {
    @fontsize lg;
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

.file-selector-button {
  @space margin-top sm;
  padding-top: 15px;
  color: #ffffff;
  border: 1px solid theme(colors.blue);
  background-color: theme(colors.blue);
  height: 60px;
  border-radius: 30px;
  padding-bottom: 0px;
  min-width: 205px;
  text-align: center;
  transition: background-color 0.25s ease, border-color 0.25s ease;

  &:hover {
    background-color: theme(colors.dark);
    border-color: theme(colors.dark);
  }
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

      .ws-normal {
        font-family: theme(typography.families.mono);
      }
    }
  }
}
</style>
