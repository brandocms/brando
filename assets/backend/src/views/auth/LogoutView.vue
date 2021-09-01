<template>
  <div>Logging out</div>
</template>

<script>

import { onLogout } from '../../vue-apollo'
import defaultAbilities from '../../services/casl/defaultAbility'

export default {
  async mounted () {
    await onLogout(this.$apolloProvider.defaultClient)
    this.$ability.update(defaultAbilities.rules)
    this.$root.ready = false
    this.$root.initialized = false
    this.$router.push('login')
  }
}
</script>
