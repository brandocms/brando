<template>
  <article v-if="<%= vue_singular %>">
    <ContentHeader>
      <template v-slot:title>
        {{ $t('<%= vue_plural %>.title') }}
      </template>
      <template v-slot:subtitle>
        {{ $t('<%= vue_plural %>.edit') }}
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
import GET_<%= String.upcase(singular) %> from '../../gql/<%= snake_domain %>/<%= String.upcase(singular) %>_QUERY.graphql'
import locale from '../../locales/<%= vue_plural %>'

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

  methods: {
    async save () {
      const <%= vue_singular %>Params = this.$utils.stripParams(
        this.<%= vue_singular %>, [
          '__typename',
          'id',
          'inserted_at',
          'updated_at',
          'deleted_at'<%= if creator do %>,
          'creator'<% end %><%= if gallery do %>,
          <%= for {{_k, v}, idx} <- Enum.with_index(gallery_fields) do %>'<%= v %>'<%= unless idx == Enum.count(gallery_fields) - 1 do %>,<% end %><% end %><% end %>
        ]
      )

      <%= if img_fields != [] do %>this.$utils.validateImageParams(<%= vue_singular %>Params, <%= img_fields |> Enum.map(&(to_charlist(elem(&1, 1)))) |> inspect %>)<% end %>

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation Update<%= Recase.to_pascal(vue_singular) %>($<%= vue_singular %>Id: ID!, $<%= vue_singular %>Params: <%= Recase.to_pascal(vue_singular) %>Params) {
              update<%= Recase.to_pascal(vue_singular) %>(
                <%= vue_singular %>Id: $<%= vue_singular %>Id,
                <%= vue_singular %>Params: $<%= vue_singular %>Params
              ) {
                id
              }
            }
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
      query: GET_<%= String.upcase(singular) %>,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          <%= vue_singular %>Id: this.<%= vue_singular %>Id
        }
      },

      skip () {
        return !this.<%= vue_singular %>Id
      }
    }
  },

  i18n: {
    sharedMessages: locale
  }
}
</script>

<style lang="postcss" scoped>

</style>
