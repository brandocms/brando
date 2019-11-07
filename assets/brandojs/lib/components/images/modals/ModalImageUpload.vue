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
              v-if="files.length"
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
                    <i class="fal fa-fw fa-check text-success" />
                  </td>
                  <td
                    v-else-if="file.active"
                    key="active"
                    class="fit">
                    <i class="fal fa-fw fa-cog fa-spin" />
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
              v-else
              class="d-flex justify-content-center p-5 mt-0 mb-4 bg-light">
              <h5 class="text-center">
                Slipp filene dine her for å laste opp<br><br>eller
              </h5>
            </div>
            <div class="d-flex justify-content-center">
              <div class="example-btn">
                <FileUpload
                  ref="upload"
                  v-model="files"
                  :post-action="`/admin/api/images/upload/image_series/${imageSeries.id}`"
                  :headers="{'authorization': getToken()}"
                  :multiple="true"
                  :drop="true"
                  class="btn btn-primary mb-0"
                  name="image"
                  accept="image/*"
                  @input-filter="inputFilter"
                  @input-file="inputFile">
                  <i class="fa fa-plus" />
                  Velg filer
                </FileUpload>
                <button
                  v-if="!$refs.upload || !$refs.upload.active"
                  :disabled="!files.length"
                  type="button"
                  class="btn btn-success"
                  @click.prevent="$refs.upload.active = true">
                  <i
                    class="fa fa-arrow-up"
                    aria-hidden="true" />
                  Start opplasting
                </button>
                <button
                  v-else
                  type="button"
                  class="btn btn-danger"
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
      const token = this.$store.getters['users/token']
      return `Bearer: ${token}`
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
  }
}
</script>

<style>
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
</style>
