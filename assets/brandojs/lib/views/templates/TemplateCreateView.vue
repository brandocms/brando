<template>
  <div class="create-template">
    <div class="container">
      <div class="row">
        <div class="col">
          <div class="card h-100">
            <div class="card-header">
              <h5 class="section mb-0">
                Opprett mal
              </h5>
            </div>
            <div class="card-body">
              <VillainBuilder />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import nprogress from 'nprogress'
import showError from 'brandojs/lib/utils/showError'
import { alertError } from 'brandojs/lib/utils/alerts'
import { mapGetters } from 'vuex'

export default {
  data () {
    return {
      loading: 0
    }
  },

  computed: {
    ...mapGetters('config', [
      'settings'
    ])
  },

  inject: [
    'adminChannel'
  ],

  created () {
  }
}
</script>
