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

  data () {
    return {
      // ...
      queryVars: {
        matches: { id: this.<%= vue_singular %>Id }
      }
    }
  },

  methods: {
    async save (setLoader, revision = 0) {
      setLoader(true)
      const <%= vue_singular %>Params = this.$utils.stripParams(
        this.<%= vue_singular %>, [
          '__typename',
          'id',
          'insertedAt',
          'updatedAt',
          'deletedAt'<%= if creator do %>,
          'creator'<% end %><%= if gallery do %>,
          <%= for {{_k, v}, idx} <- Enum.with_index(gallery_fields) do %>'<%= Recase.to_camel(to_string(v)) %>'<%= unless idx == Enum.count(gallery_fields) - 1 do %>,<% end %><% end %><% end %>
        ]
      )

      <%= if img_fields != [] do %>this.$utils.validateImageParams(<%= vue_singular %>Params, <%= img_fields |> Enum.map(&(to_charlist(elem(&1, 1)))) |> inspect %>)<% end %>
      <%= if file_fields != [] do %>this.$utils.validateFileParams(<%= vue_singular %>Params, <%= file_fields |> Enum.map(&(to_charlist(Recase.to_camel(to_string(elem(&1, 1)))))) |> inspect %>)<% end %>
      <%= if villain_fields != [] do %>this.$utils.serializeParams(<%= vue_singular %>Params, <%= villain_fields |> Enum.map(&(to_charlist(Recase.to_camel(to_string(elem(&1, 1)))))) |> inspect %>)<% end %>

      // if you have MultiSelects -- they must be mapped out:
      // this.$utils.mapMultiSelects(<%= vue_singular %>Params, ['fieldName'])

      // if you have input tables that are sending objects -- the type names must be stripped:
      // this.$utils.stripTypenames(<%= vue_singular %>Params, ['fieldName'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation Update<%= Recase.to_pascal(vue_singular) %>($<%= vue_singular %>Id: ID!, $<%= vue_singular %>Params: <%= Recase.to_pascal(vue_singular) %>Params, $revision: ID) {
              update<%= Recase.to_pascal(vue_singular) %>(
                <%= vue_singular %>Id: $<%= vue_singular %>Id,
                <%= vue_singular %>Params: $<%= vue_singular %>Params,
                revision: $revision
              ) {
                id
              }
            }
          `,
          variables: {
            <%= vue_singular %>Params,
            <%= vue_singular %>Id: this.<%= vue_singular %>Id,
            revision
          }
        })
        setLoader(false)
        this.$toast.success({ message: this.$t('<%= vue_plural %>.edited') })
        if (revision === 0) {
          this.$router.push({ name: '<%= vue_plural %>' })
        }
      } catch (err) {
        setLoader(false)
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    <%= vue_singular %>: {
      query: GET_<%= String.upcase(singular) %>,
      fetchPolicy: 'no-cache',
      variables () {
        return this.queryVars
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
