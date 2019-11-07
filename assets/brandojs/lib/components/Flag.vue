<template>
  <div class="flag-wrapper">
    <span :class="'flag' + ' ' + value" />
  </div>
</template>

<script>
export default {
  props: {
    value: {
      type: String,
      required: true
    }
  }
}
</script>
