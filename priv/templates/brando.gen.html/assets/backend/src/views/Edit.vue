<template>
  <div class="create-<%= singular %>" v-if="!loading">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">Endre</h5>
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

  async created () {
    this.loading++
    const v = await <%= singular %>API.get<%= String.capitalize(singular) %>(this.<%= singular %>Id)
    this.<%= singular %> = {...v}
    this.loading--
  },

  props: {
    <%= singular %>Id: {
      type: String,
      required: true
    }
  },

  methods: {
    validate () {
      this.inject()

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

      // strip out params we don't want sent in the mutation
      stripParams(params, ['__typename', 'id'])
      // validate image params, if any, to ensure they are files
      // validateImageParams(params, ['avatar'])

      try {
        nprogress.start()
        await <%= singular %>API.update<%= String.capitalize(singular) %>(this.<%= singular %>.id, params)
        nprogress.done()
        this.$toast.success({message: 'Objekt endret'})
        this.$router.push({ name: '<%= plural %>' })
      } catch (err) {
        showError(err)
      }
    },

    inject () {
      // if the model has a VILLAIN field, uncomment this. `data` is the data field with villain json.
      // this.<%= singular %>.data = this.$refs.villain.$villain.getJSON()
    }
  }
}
</script>
