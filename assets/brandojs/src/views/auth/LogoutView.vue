<template>
  <div>Logging out</div>
</template>

<script>

import { onLogout } from '../../vue-apollo'

export default {
  async created () {
    localStorage.removeItem('token')
    await onLogout(this.$apolloProvider.defaultClient)
    this.$router.push('login')
  }
}
</script>

<style>

</style>
