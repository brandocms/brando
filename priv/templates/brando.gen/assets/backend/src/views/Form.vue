<template>
  <KForm
    v-if="<%= vue_singular %>"
    :back="{ name: '<%= vue_plural %>' }"
    @save="save">
    <section class="row">
      <div class="half">
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
import locale from '../../locales/<%= vue_plural %>'
// __imports

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