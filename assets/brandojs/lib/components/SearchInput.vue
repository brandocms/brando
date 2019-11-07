<template>
  <div class="search-input">
    <i class="fal fa-search search-icon" />
    <input
      v-model="innerValue"
      class="form-control"
      type="text"
      @keyup.prevent.enter="perform"
      @input="onInput">
    <i
      v-if="filtered"
      class="fal fa-window-close close-icon text-danger"
      @click="reset" />
  </div>
</template>

<script>
export default {
  props: {
    value: {
      type: String,
      default: ''
    }
  },

  data () {
    return {
      innerValue: '',
      filtered: false
    }
  },

  methods: {
    onInput () {
      this.$emit('input', this.innerValue)
    },

    perform () {
      this.filtered = true
      this.$emit('search')
    },

    reset () {
      this.innerValue = ''
      this.filtered = false
      this.$emit('reset')
    }
  }
}
</script>
