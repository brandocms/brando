<template>
  <KForm
    v-if="<%= vue_singular %>"
    :back="{ name: '<%= vue_plural %>' }"
    @save="save">
    <section class="row">
      <div class="sized">
        <!--
        FORM FIELDS HERE
        --><%= for {_, html} <- vue_inputs do %>
<%= html %>
        <% end %>
      </div>
    </section>
  </KForm>
</template>

<script>
// ++imports
import locale from '../../locales/<%= vue_plural %>'<%= if revisioned do %>
import Revisions from 'brandojs/src/mixins/Revisions'<% end %><%= if meta do %>
import Meta from 'brandojs/src/mixins/Meta'<% end %><%= if publish_at do %>
import ScheduledPublishing from 'brandojs/src/mixins/ScheduledPublishing'<% end %>

// __imports

export default {
  mixins: [<%= if revisioned do %>
    Revisions({
      schema: '<%= schema_module %>',
      prop: '<%= vue_singular %>',
      key: 'id'
    }),
    <% end %><%= if meta do %>
    Meta({
      prop: '<%= vue_singular %>'
    }),
    <% end %><%= if publish_at do %>
    ScheduledPublishing({
      prop: '<%= vue_singular %>'
    }),
    <% end %>
  ],
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

  // ++apollo
  <%= vue_form_queries %>
  // __apollo

  i18n: {
    sharedMessages: locale
  }
}
</script>

<style lang="postcss" scoped>

</style>