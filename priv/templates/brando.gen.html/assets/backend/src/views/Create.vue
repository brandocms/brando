<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        <%= plural %> admin
      </template>
    </ContentHeader>
    <<%= Recase.to_pascal(vue_singular) %>Form
      :<%= vue_singular %>="<%= vue_singular %>"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import <%= Recase.to_pascal(vue_singular) %>Form from './<%= Recase.to_pascal(vue_singular) %>Form'
import <%= String.upcase(singular) %>_FRAGMENT from './gql/<%= String.upcase(singular) %>_FRAGMENT.graphql'
import GET_<%= String.upcase(plural) %> from './gql/<%= String.upcase(plural) %>_QUERY.graphql'

export default {
  components: {
    <%= Recase.to_pascal(vue_singular) %>Form
  },

  data () {
    return {
      <%= vue_singular %>: {}
    }
  },

  fragments: {
    <%= vue_singular %>: <%= String.upcase(singular) %>_FRAGMENT
  },

  methods: {
    async save () {
      const <%= vue_singular %>Params = this.$utils.stripParams(this.<%= vue_singular %>, ['__typename', 'id', 'inserted_at', 'updated_at', 'deleted_at'])
      this.$utils.validateImageParams(<%= vue_singular %>Params, ['avatar'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation Create<%= Recase.to_pascal(vue_singular) %>($<%= vue_singular %>Params: <%= Recase.to_pascal(vue_singular) %>Params) {
              create<%= Recase.to_pascal(vue_singular) %>(
                <%= vue_singular %>Params: $<%= vue_singular %>Params
              ) {
                ...<%= vue_singular %>
              }
            }
            ${<%= String.upcase(singular) %>_FRAGMENT}
          `,
          variables: {
            <%= vue_singular %>Params
          }
        })

        this.$toast.success({ message: 'Objekt opprettet' })
        this.$router.push({ name: '<%= vue_plural %>' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>