<template>
  <button class="btn btn-white">
    <i
      :class="getColor()"
      class="fa fa-circle" />
  </button>
</template>

<script>
export default {
  props: {
    status: {
      type: String,
      required: true
    }
  },

  methods: {
    getColor () {
      switch (this.status) {
        case 'published':
          return 'text-success'
        case 'pending':
          return 'text-warning'
        case 'deleted':
          return 'text-deleted'
        case 'draft':
          return 'text-gray'
      }
    }
  }
}
</script>
