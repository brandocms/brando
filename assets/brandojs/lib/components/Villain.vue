<template>
  <div class="villain-component">
    <div :class="{'form-group': true, 'has-danger': hasError}">
      <div class="label-wrapper">
        <label
          :for="name"
          class="control-label">
          {{ label }}
        </label>
        <span>
          <i class="fa fa-exclamation-circle text-danger" />
          {{ errorText }}
        </span>
      </div>

      <VillainEditor
        ref="villain"
        :templates="templates"
        :template-mode="templateMode"
        :json="innerValue"
        :visible-blocks="visibleBlocks"
        :extra-headers="{'authorization': `Bearer ${token}`}"
        @input="$emit('input', $event)" />
    </div>
  </div>
</template>

<script>
import { mapGetters } from 'vuex'
import VillainEditor from '@univers-agency/villain-editor'

export default {
  components: {
    VillainEditor
  },

  props: {
    hasError: {
      type: Boolean,
      default: false
    },

    errorText: {
      type: String,
      default: ''
    },

    label: {
      type: String,
      required: false,
      default: ''
    },

    imageSeries: {
      type: String,
      default: 'post'
    },

    value: {
      type: [String, Array],
      default: null
    },

    name: {
      type: String,
      required: true
    },

    templateMode: {
      type: Boolean,
      default: false
    },

    templates: {
      type: String,
      default: 'all'
    },

    visibleBlocks: {
      type: Array,
      default: () => []
    }
  },

  data () {
    return {
      innerValue: null
    }
  },

  computed: {
    ...mapGetters('users', ['token'])
  },

  $_veeValidate: {
    name () {
      return this.name
    }
  },

  watch: {
    value (value) {
      this.innerValue = value
    }
  },

  created () {
    this.innerValue = this.value
  }
}
</script>
