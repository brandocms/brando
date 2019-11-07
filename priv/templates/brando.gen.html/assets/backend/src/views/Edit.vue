<template>
  <div class="create-<%= singular %>" v-if="!loading">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">Endre</h5>
        </div>
        <div class="card-body">
          <<%= Recase.to_pascal(vue_singular) %>Form
            :<%= vue_singular %>="<%= vue_singular %>"
            :loading="loading"
            @validate="validate" />
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
import <%= Recase.to_pascal(vue_singular) %>Form from '@/views/<%= snake_domain %>/<%= Recase.to_pascal(vue_singular) %>Form'

export default {
  components: {
    <%= Recase.to_pascal(vue_singular) %>Form
  },

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
    this.<%= vue_singular %> = { ...v }
    this.loading--
  },

  props: {
    <%= vue_singular %>Id: {
      type: String,
      required: true
    }
  },

  methods: {
    async save () {
      this.loading = 0
      let params = { ...this.<%= vue_singular %> }

      // strip out params we don't want sent in the mutation
      stripParams(params, ['__typename', 'id'])

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
        await <%= singular %>API.update<%= Recase.to_pascal(vue_singular) %>(this.<%= vue_singular %>.id, params)
        nprogress.done()
        this.$toast.success({ message: 'Objekt endret' })
        this.$router.push({ name: '<%= plural %>' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
