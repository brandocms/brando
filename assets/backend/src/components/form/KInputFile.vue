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
    </template>
    <template #default="{ provider }">
      <FileInput
        :id="id"
        ref="fileInput"
        :current-file="innerValue"
        :name="name"
        :custom-strings="customStrings"
        accept="*"
        :size="sizeLimit"
        button-class="btn btn-outline-secondary"
        @init="provider.validate($event)"
        @change="onChange($event) || provider.validate($event)"
        @remove="onRemove() || provider.validate(null)" />
    </template>
  </KFieldBase>
</template>

<script>
import FileInput from './utils/FileInput.vue'

export default {
  components: {
    FileInput
  },

  props: {
    hasError: {
      type: Boolean,
      default: false
    },

    sizeLimit: {
      type: Number,
      default: 3
    },

    helpText: {
      type: String,
      default: null
    },

    errorText: {
      type: String,
      default: ''
    },

    label: {
      type: String,
      required: true
    },

    rules: {
      type: String,
      default: null
    },

    name: {
      type: String,
      required: true
    },

    value: {
      required: false,
      default: null,
      type: null
    }
  },

  data () {
    return {
      loading: 0,
      preCheck: false,
      innerValue: '',
      showErrorModal: false,
      prefill: null,
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
      this.innerValue = value
    }
  },

  created () {
    this.innerValue = this.value
    if (typeof this.value === 'string') {
      this.prefill = this.value
    } else {
      this.prefill = this.value ? this.value.url : null
    }
  },

  methods: {
    onChange (a) {
      this.innerValue = a
    },

    onRemove (a) {
      this.innerValue = null
    }
  }
}
</script>

<i18n>
{
  "en": {
    "close": "Close",
    "error": "Error",
    "upload": "Your device does not support file uploads :(",
    "drag": "Click or drop your file her",
    "tap": "Tap to pick an file from your computer",
    "change": "Change file",
    "remove": "Reset filefield",
    "select": "Select file",
    "meta": "Edit file info",
    "fileSize": "File is too large!",
    "fileSizeError": "The file you are trying to upload is too big. <br><br>Max allowed size for the field is <br><br>&lt;&lt; {sizeLimit}MB. &gt;&gt;<br><br>Try compressing the file with an online service<br>like <a href=\"https://squoosh.app/\" target=\"_blank\" rel=\"noopener nofollow\">squoosh.app</a> or a mac app like <a href=\"https://imageoptim.com/mac/\" target=\"_blank\" rel=\"noopener nofollow\">ImageOptim</a>.",
    "fileType": "File type not supported",
    "fileTypeError": "Disallowed file type. <br><br>Valid file types for this field are<br><br>&lt;&lt; {accept} &gt;&gt;<br><br>"
  },
  "no": {
    "close": "Lukk",
    "error": "Feil",
    "upload": "Dingsen du bruker støtter ikke filopplasting :(",
    "drag": "Klikk eller slipp filen ditt her",
    "tap": "Tapp her for å velge en fil fra harddisken din",
    "change": "Skift fil",
    "remove": "Nullstill filfelt",
    "select": "Velg en fil",
    "meta": "Endre filinformasjon",
    "fileSize": "Filen er for stor!",
    "fileSizeError": "Filen du vil laste opp er for stor. <br><br>Maks tillatt størrelse for feltet er <br><br>&lt;&lt; {sizeLimit}MB. &gt;&gt;<br><br>Du kan komprimere filen før du laster den opp med en online tjeneste<br>som <a href=\"https://squoosh.app/\" target=\"_blank\" rel=\"noopener nofollow\">squoosh.app</a> eller en mac-applikasjon som f.eks <a href=\"https://imageoptim.com/mac/\" target=\"_blank\" rel=\"noopener nofollow\">ImageOptim</a>.",
    "fileType": "Filtypen er ikke støttet",
    "fileTypeError": "Ikke tillatt filtype. <br><br>Gyldige filtyper for dette felter er<br><br>&lt;&lt; {accept} &gt;&gt;<br><br>"
  }
}
</i18n>
