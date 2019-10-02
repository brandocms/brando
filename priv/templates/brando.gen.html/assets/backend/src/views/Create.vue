<template>
  <div class="create-<%= vue_singular %>">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">Opprett</h5>
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

import { nprogress } from '@univers-agency/kurtz'
import { showError, validateImageParams, stripParams } from '@univers-agency/kurtz/lib/utils'
import { alertError } from '@univers-agency/kurtz/lib/utils/alerts'
import { <%= vue_singular %>API } from '@/api/<%= vue_singular %>'

export default {
  data () {
    return {
      loading: 0,
      <%= vue_singular %>: {<%= for {v, d} <- vue_defaults do %>
        <%= v %>: <%= d %>,<% end %>
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
      this.$validator.validateAll().then(valid => {
        if (!valid) {
          alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
          this.loading = false
          return
        }
        this.save()
      }).catch(err => {
        console.log(err)
      })
    },

    async save () {
      this.loading = false
      let params = { ...this.<%= vue_singular %> }

      <%= if Enum.count(img_fields) > 0 do %>
      // validate image params, if any, to ensure they are files
      <%
        fs =
          img_fields
          |> Enum.map(fn {_v, k} -> ~s('#{k}') end)
          |> Enum.join()
      %>validateImageParams(params, [<%= fs %>])<% end %>

      try {
        nprogress.start()
        await <%= vue_singular %>API.create<%= Recase.to_pascal(vue_singular) %>(params)
        nprogress.done()
        this.$toast.success({ message: 'Objekt opprettet' })
        this.$router.push({ name: '<%= plural %>' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
