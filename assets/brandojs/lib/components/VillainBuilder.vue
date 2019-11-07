<template>
  <div class="villain-component">
    <VillainEditor
      ref="villain"
      :builder-mode="true"
      :extra-headers="{'authorization': `Bearer ${token}`}"
      @input="$emit('input', $event)" />
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
    templateMode: {
      type: Boolean,
      default: false
    },

    templates: {
      type: String,
      default: 'all'
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
