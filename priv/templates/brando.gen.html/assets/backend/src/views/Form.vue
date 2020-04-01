<template>
  <KForm
    v-if="<%= vue_singular %>"
    :back="{ name: '<%= vue_plural %>' }"
    @save="save">
    <section class="row">
      <div class="half">
        <!--
        FORM FIELDS HERE
        --><%= for {_v, k} <- vue_inputs do %>
        <%= List.first(k) %><% {_, r} = List.pop_at(k, 0); {_, remainder} = List.pop_at(r, -1) %><%= for prop <- remainder do %>
          <%= prop %><% end %>
        />
        <% end %>
      </div>
    </section>
  </KForm>
</template>

<script>
import locale from '../../locales/<%= vue_plural %>'
export default {
  props: {
    <%= vue_singular %>: {
      type: Object,
      default: () => {}
    },

    save: {
      type: Function,
      required: true
    }
  },

  data () {
    return {
      parents: [],
      settings: {
        templateMode: false,
        templateNamespace: 'all',
        namespacedTemplates: []
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    //
  },

  methods: {
    //
  },

  i18n: {
    sharedMessages: locale
  }
}
</script>

<style lang="postcss" scoped>

</style>