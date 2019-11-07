<template>
  <i
    v-if="val"
    :class="'fal fa-check-circle' + (colored ? ' text-success' : '')"
    aria-hidden="true" />
  <i
    v-else-if="!val && !blankIfFalse"
    :class="'fal fa-times-circle' + (colored ? ' text-danger' : '')"
    aria-hidden="true" />
</template>
<script>
export default {
  props: {
    val: {
      type: Boolean,
      required: true
    },

    colored: {
      type: Boolean,
      default: false
    },

    blankIfFalse: {
      type: Boolean,
      default: false,
      required: false
    }
  }
}
</script>
