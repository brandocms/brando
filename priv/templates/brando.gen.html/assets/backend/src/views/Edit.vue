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
          --><%= for {_v, k} <- vue_inputs do %>
          <%= List.first(k) %><% {_, r} = List.pop_at(k, 0); {_, remainder} = List.pop_at(r, -1) %><%= for prop <- remainder do %>
            <%= prop %><% end %>
          />
          <% end %>
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
import { <%= vue_singular %>API } from '@/api/<%= vue_singular %>'

export default {
  data () {
    return {
      loading: 0,
      <%= vue_singular %>: null
    }
  },

  inject: [
    'adminChannel'
  ],

  async created () {
    this.loading++
    const v = await <%= vue_singular %>API.get<%= Recase.to_pascal(vue_singular) %>(this.<%= vue_singular %>Id)
    this.<%= vue_singular %> = {...v}
    this.loading--
  },

  props: {
    <%= vue_singular %>Id: {
      type: String,
      required: true
    }
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
      let params = {...this.<%= vue_singular %>}

      // strip out params we don't want sent in the mutation
      stripParams(params, ['__typename', 'id'])

      // validate image params, if any, to ensure they are files
      // validateImageParams(params, ['avatar'])

      try {
        nprogress.start()
        await <%= singular %>API.update<%= Recase.to_pascal(vue_singular) %>(this.<%= vue_singular %>.id, params)
        nprogress.done()
        this.$toast.success({message: 'Objekt endret'})
        this.$router.push({ name: '<%= plural %>' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
