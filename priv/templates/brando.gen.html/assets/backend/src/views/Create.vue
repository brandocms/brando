<template>
  <div class="create-<%= singular %>">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">Opprett</h5>
        </div>
        <div class="card-body">
          <!--
          FORM FIELDS HERE
          -->
          <button :disabled="!!loading" @click="validate" class="btn btn-secondary">
            Lagre
          </button>

          <router-link :disabled="!!loading" :to="{ name: '<%= plural %>' }" class="btn btn-outline-secondary">
            Tilbake til oversikten
          </router-link>
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import nprogress from 'nprogress'
import { showError, validateImageParams, stripParams } from 'kurtz/lib/utils'
import { <%= singular %>API } from '@/api/<%= singular %>'

export default {
  data () {
    return {
      loading: 0,
      <%= singular %>: {
        // add fields
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {

  },

  methods: {
    validate () {
      this.$validator.validateAll().then(() => {
        this.save()
      }).catch(err => {
        console.log(err)
        alert('Feil i skjema', 'Vennligst se over og rett feil i rødt')
        this.loading = false
      })
    },

    async save () {
      this.loading = false
      let params = {...this.<%= singular %>}

      // validate image params, if any, to ensure they are files
      validateImageParams(params, [])

      try {
        nprogress.start()
        await <%= singular %>API.create<%= String.capitalize(singular) %>(params)
        nprogress.done()
        this.$toast.success({message: 'Objekt opprettet'})
        this.$router.push({ name: '<%= plural %>' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
