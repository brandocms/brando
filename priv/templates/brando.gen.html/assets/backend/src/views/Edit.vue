<template>
  <article v-if="<%= vue_singular %>">
    <ContentHeader>
      <template v-slot:title>
        <%= plural %> admin
      </template>
      <template v-slot:subtitle>
        Edit <%= singular %>
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
import <%= String.upcase(singular) %>_FRAGMENT from './gql/<%= String.upcase(singular) %>_FRAGMENT.graphql

export default {
  components: {
    <%= Recase.to_pascal(vue_singular) %>Form
  },

  props: {
    <%= vue_singular %>Id: {
      type: [String, Number],
      required: true
    }
  },

  data () {
    return {
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
            mutation Update<%= Recase.to_pascal(vue_singular) %>($<%= vue_singular %>Id: ID!, $<%= vue_singular %>Params: <%= Recase.to_pascal(vue_singular) %>Params) {
              update<%= Recase.to_pascal(vue_singular) %>(
                <%= vue_singular %>Id: $<%= vue_singular %>Id,
                <%= vue_singular %>Params: $<%= vue_singular %>Params
              ) {
                ...<%= vue_singular %>
              }
            }
            ${<%= String.upcase(singular) %>_FRAGMENT}
          `,
          variables: {
            <%= vue_singular %>Params,
            <%= vue_singular %>Id: this.<%= vue_singular %>Id
          }
        })

        this.$toast.success({ message: 'Entry updated' })
        this.$router.push({ name: '<%= vue_plural %>' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    <%= vue_singular %>: {
      query: gql`
        query <%= Recase.to_pascal(vue_singular) %> ($<%= vue_singular %>Id: ID!) {
          <%= vue_singular %> (<%= vue_singular %>Id: $<%= vue_singular %>Id) {
            ...<%= vue_singular %>
          }
        }
        ${<%= String.upcase(singular) %>_FRAGMENT}
      `,
      variables () {
        return {
          <%= vue_singular %>Id: this.<%= vue_singular %>Id
        }
      },

      skip () {
        return !this.<%= vue_singular %>Id
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
