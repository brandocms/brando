<template>
  <KFieldBase
    :name="name"
    :label="label + ' (max ' + sizeLimit + 'MB)'"
    :rules="rules"
    :help-text="helpText"
    :value="innerValue">
    <template #outsideValidator>
      <KModal
        v-if="showErrorModal"
        ref="errorModal"
        v-shortkey="['esc', 'enter']"
        :ok-text="$t('close')"
        @shortkey.native="closeErrorModal"
        @ok="closeErrorModal">
        <template #header>
          {{ $t('error') }}
        </template>
        <div v-html="errorMessage" />
      </KModal>

      <KModal
        v-if="showEditModal"
        ref="editModal"
        v-shortkey="['esc', 'enter']"
        :ok-text="$t('close')"
        @shortkey.native="closeEditModal"
        @ok="closeEditModal">
        <template #header>
          {{ $t('edit-image-data') }}
        </template>
        <KInput
          v-model="innerValue.title"
          rules=""
          name="image[title]"
          label="Bildetekst"
          placeholder="Bildetekst" />
        <KInput
          v-model="innerValue.alt"
          rules=""
          name="image[alt]"
          label="Alt. tekst"
          placeholder="Beskrivelse av bildet" />
      </KModal>
    </template>
    <template #default="{ provider }">
      <div
        v-if="provider"
        class="image-preview-wrapper">
        <template v-if="!small">
          <PictureInput
            :id="id"
            ref="pictureInput"
            :size-limit="sizeLimit"
            :focal="focal"
            :crop="crop"
            :width="width"
            :height="height"
            :prefill="prefill"
            :removable="true"
            :name="name"
            :custom-strings="customStrings"
            :size="sizeLimit"
            :accept="accept"
            margin="0"
            button-class="btn btn-outline-secondary"
            @click.prevent
            @init="provider.validate($event)"
            @change="onChange(provider, $event)"
            @remove="onRemove(provider)"
            @error="onError"
            @focalChanged="onFocalChanged" />
          <ButtonSecondary
            v-if="edit && innerValue"
            class="btn-edit"
            @click="showEditModal = true">
            {{ $t('edit-image-data') }}
          </ButtonSecondary>
        </template>

        <div
          v-else
          class="image-preview-wrapper-small">
          <transition @appear="initialValidation(provider)">
            <span></span>
          </transition>
          <KModal
            v-if="showModal"
            ref="modal"
            v-shortkey="['esc']"
            :ok-text="$t('close')"
            @shortkey.native="closeModal"
            @ok="closeModal">
            <template #header>
              {{ $t('edit-image') }}
            </template>
            <PictureInput
              :id="id"
              ref="pictureInput"
              :size-limit="sizeLimit"
              :focal="focal"
              :crop="crop"
              :width="width"
              :height="height"
              :prefill="prefill"
              :removable="true"
              :name="name"
              :custom-strings="customStrings"
              :size="sizeLimit"
              :accept="accept"
              margin="0"
              button-class="btn btn-outline-secondary"
              @click.prevent
              @init="provider.validate($event)"
              @change="onChange(provider, $event)"
              @remove="onRemove(provider)"
              @error="onError"
              @focalChanged="onFocalChanged" />
            <ButtonSecondary
              v-if="edit && innerValue"
              class="btn-edit"
              @click="showEditModal = true">
              {{ $t('edit-image-data') }}
            </ButtonSecondary>
          </KModal>

          <div
            v-if="prefill"
            class="prefill-small">
            <figure
              class="preview-image-wrapper"
              @click="showModal = true">
              <img
                v-if="previewImage"
                :src="previewImage"
                class="preview-image" />
              <img
                v-else
                :src="prefill"
                class="preview-image" />
            </figure>
            <div>&larr; {{ $t('click-to-edit') }}</div>
          </div>

          <div v-else>
            <!-- no image -->
            <ButtonSecondary
              @click="showModal = true">
              {{ $t('upload-image') }}
            </ButtonSecondary>
          </div>
        </div>
      </div>
    </template>
  </KFieldBase>
</template>

<script>
import PictureInput from './utils/PictureInput'

export default {
  components: {
    PictureInput
  },

  props: {
    previewKey: {
      type: String,
      default: 'thumb'
    },

    small: {
      type: Boolean,
      default: false
    },

    accept: {
      type: String,
      default: 'image/jpeg,image/jpg,image/png,image/gif'
    },

    sizeLimit: {
      type: Number,
      default: 3
    },

    helpText: {
      type: String,
      default: null
    },

    crop: {
      type: Boolean,
      default: false
    },

    width: {
      type: Number,
      default: 450
    },

    height: {
      type: Number,
      default: 450
    },

    label: {
      type: String,
      required: true
    },

    name: {
      type: String,
      required: true
    },

    edit: {
      type: Boolean,
      default: true
    },

    rules: {
      type: String,
      default: null
    },

    value: {
      required: false,
      default: null,
      type: null
    }
  },

  data () {
    return {
      firstPrefill: true,
      focal: null,
      loading: 0,
      preCheck: false,
      innerValue: '',
      prefill: null,
      showModal: false,
      showEditModal: false,
      showErrorModal: false,
      previewImage: null,
      errorMessage: '',

      customStrings: {
        upload: this.$t('upload'),
        drag: this.$t('drag'),
        tap: this.$t('tap'),
        change: this.$t('change'),
        remove: this.$t('remove'),
        select: this.$t('select'),
        meta: this.$t('meta'),
        fileSize: this.$t('fileSize'),
        fileType: this.$t('fileType')
      }
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    }
  },

  watch: {
    innerValue (value) {
      this.$emit('input', value)
    },

    value (value) {
      this.initialize()
    }
  },

  mounted () {
    this.initialize()
  },

  methods: {
    initialize (from) {
      this.innerValue = this.value
      this.setPrefill()

      this.$nextTick(() => {
        if (this.$refs.provider) {
          this.$refs.provider.validate(this.value)
        }
      })
    },

    initialValidation (provider) {
      provider.validate(this.value)
    },

    setPrefill () {
      this.prefill = this.innerValue ? this.innerValue[this.previewKey] : null
      if (this.innerValue) {
        this.focal = this.innerValue.focal ? this.innerValue.focal : null
        if (this.firstPrefill) {
          delete this.innerValue.focal
        }
        this.firstPrefill = false
      } else {
        this.focal = { x: 50, y: 50 }
      }
    },

    async closeModal () {
      await this.$refs.modal.close()
      this.showModal = false
    },

    async closeEditModal () {
      await this.$refs.editModal.close()
      this.showEditModal = false
    },

    async closeErrorModal () {
      await this.$refs.errorModal.close()
      this.showErrorModal = false
    },

    showError () {
      this.showErrorModal = true
    },

    async hideError () {
      await this.$refs.errorModal.close()
      this.showErrorModal = false
    },

    toBase64 (file) {
      return new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.readAsDataURL(file)
        reader.onload = () => {
          resolve(reader.result)
        }
        reader.onerror = error => {
          reject(error)
        }
      })
    },

    async onChange (provider, a) {
      /*
      This triggers on the initial load of prefill, as well as when the image changes.
      */
      provider.validate(a)

      if (this.value && !this.preCheck) {
        // Just changing the prefill. Set preCheck and return
        this.preCheck = true
        return
      }

      // there's been a change, and we either have no prefill, or we've triggered the prefill check:
      if (this.$refs.pictureInput.file) {
        this.preCheck = true

        const base64file = await this.toBase64(this.$refs.pictureInput.file)

        this.innerValue = {
          file: this.$refs.pictureInput.file,
          thumb: this.$refs.pictureInput.file,
          original: this.$refs.pictureInput.file,
          xlarge: this.$refs.pictureInput.file,
          base64: base64file,
          alt: '',
          title: ''
        }

        if (this.small && this.innerValue) {
          this.previewImage = a
          this.prefill = this.$refs.pictureInput.file
        }
      }
    },

    onRemove (provider) {
      this.innerValue = null
      provider.validate(this.innerValue)
      this.setPrefill()
    },

    onFocalChanged (f) {
      if (this.preCheck) {
        this.setFocal(f)
      }
    },

    onError (err) {
      switch (err.type) {
        case 'fileSize':
          this.errorMessage = this.$t('fileSizeError', { sizeLimit: this.sizeLimit })
          this.showError()
          break

        case 'fileType':
          this.errorMessage = this.$t('fileTypeError', { accept: this.accept })
          this.showError()
          break
      }
    },

    setFocal (f) {
      this.$set(this.innerValue, 'focal', f)
    }
  }
}
</script>
<style lang="postcss" scoped>
  .preview-image-wrapper {
    width: 75px;
    height: 75px;

    .preview-image {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }

  .prefill-small {
    display: flex;
    align-items: center;
    border: 1px solid theme(colors.dark);

    div {
      padding-left: 50px;
    }
  }

  .btn-edit {
    width: 100%;
    margin-top: -1px;
  }
</style>

<i18n>
{
  "en": {
    "click-to-edit": "Click image to edit",
    "edit-image": "Edit image",
    "upload-image": "Upload image",
    "edit-image-data": "Edit image data",
    "error": "Error",
    "close": "Close",
    "upload": "Your device does not support file uploads :(",
    "drag": "Click or drop your image her",
    "tap": "Tap to pick an image from your gallery",
    "change": "Change image",
    "remove": "Reset imagefield",
    "select": "Select image",
    "meta": "Edit image info",
    "fileSize": "File is too large!",
    "fileSizeError": "The file you are trying to upload is too big. <br><br>Max allowed size for the field is <br><br>&lt;&lt; {sizeLimit}MB. &gt;&gt;<br><br>Try compressing the file with an online service<br>like <a href=\"https://squoosh.app/\" target=\"_blank\" rel=\"noopener nofollow\">squoosh.app</a> or a mac app like <a href=\"https://imageoptim.com/mac/\" target=\"_blank\" rel=\"noopener nofollow\">ImageOptim</a>.",
    "fileType": "File type not supported",
    "fileTypeError": "Disallowed file type. <br><br>Valid file types for this field are<br><br>&lt;&lt; {accept} &gt;&gt;<br><br>"
  },
  "no": {
    "click-to-edit": "Klikk på bildet for å redigere/endre",
    "edit-image": "Rediger bilde",
    "upload-image": "Last opp bilde",
    "edit-image-data": "Endre bildedata",
    "error": "Feil",
    "close": "Lukk",
    "upload": "Dingsen du bruker støtter ikke filopplasting :(",
    "drag": "Klikk eller slipp bildet ditt her",
    "tap": "Tapp her for å velge et bilde fra galleriet ditt",
    "change": "Skift bilde",
    "remove": "Nullstill bildefelt",
    "select": "Velg et bilde",
    "meta": "Endre bildeinformasjon",
    "fileSize": "Filen er for stor!",
    "fileSizeError": "Filen du vil laste opp er for stor. <br><br>Maks tillatt størrelse for feltet er <br><br>&lt;&lt; {sizeLimit}MB. &gt;&gt;<br><br>Du kan komprimere filen før du laster den opp med en online tjeneste<br>som <a href=\"https://squoosh.app/\" target=\"_blank\" rel=\"noopener nofollow\">squoosh.app</a> eller en mac-applikasjon som f.eks <a href=\"https://imageoptim.com/mac/\" target=\"_blank\" rel=\"noopener nofollow\">ImageOptim</a>.",
    "fileType": "Filtypen er ikke støttet",
    "fileTypeError": "Ikke tillatt filtype. <br><br>Gyldige filtyper for dette felter er<br><br>&lt;&lt; {accept} &gt;&gt;<br><br>"
  }
}
</i18n>
