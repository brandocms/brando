<template>
  <div class="create-<%= vue_singular %>">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">Opprett</h5>
        </div>
        <div class="card-body">
          <<%= Recase.to_pascal(vue_singular) %>Form
            :<%= vue_singular %>="<%= vue_singular %>"
            :loading="loading"
            @save="save" />
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import { nprogress } from 'brandojs'
import { showError, validateImageParams, stripParams } from 'brandojs/lib/utils'
import { alertError } from 'brandojs/lib/utils/alerts'
import { <%= vue_singular %>API } from '@/api/<%= vue_singular %>'
import <%= Recase.to_pascal(vue_singular) %>Form from '@/views/<%= snake_domain %>/<%= Recase.to_pascal(vue_singular) %>Form'

export default {
  components: {
    <%= Recase.to_pascal(vue_singular) %>Form
  },

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
    console.log('<%= Recase.to_pascal(vue_singular) %>CreateView created')
  },

  methods: {
    async save () {
      this.loading = 0
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
