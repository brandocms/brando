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
          Last opp bilder til &laquo;<strong>{{ imageSeries.name }}</strong>&raquo;
        </h5>
      </div>
      <div class="card-body">
        <Dropzone
          v-show="!files.length"
          :image-series-id="imageSeries.id"
          @close="closeModal"
          @save="$emit('save', $event)" />
      </div>
    </div>
  </modal>
</template>

<script>
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
            // massage the file a bit
            const image = {
              ...newFile.response.image,
              __typename: 'Image',
              image: {
                ...newFile.response.image.image,
                __typename: 'ImageType',
                medium: newFile.response.image.image.sizes.medium,
                thumb: newFile.response.image.image.sizes.thumb
              }
            }
            this.$emit('save', image)
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
        const URL = window.URL || window.webkitURL
        if (URL && URL.createObjectURL) {
          newFile.blob = URL.createObjectURL(newFile.file)
        }
        newFile.thumb = ''
        if (newFile.blob && newFile.type.substr(0, 6) === 'image/') {
          newFile.thumb = newFile.blob
        }
      }
    }
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

  &:hover {
    background-color: theme(colors.dark);
    border-color: theme(colors.dark);
  }
}
</style>
