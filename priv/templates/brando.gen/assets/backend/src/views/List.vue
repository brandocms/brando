<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        {{ $t('<%= vue_plural %>.title') }}
      </template>
      <template v-slot:subtitle>
        {{ $t('<%= vue_plural %>.subtitle') }}
      </template>
      <template v-slot:help>
        <p>
          {{ $t('<%= vue_plural %>.help-text') }}
        </p>
      </template>
    </ContentHeader>

    <div class="row baseline">
      <div class="half">
        <h2>
          {{ $t('<%= vue_plural %>.index') }}
        </h2>
      </div>
      <div class="half">
        <Dropdown>
          <template v-slot:default>
            {{ $t('<%= vue_plural %>.actions') }}
          </template>
          <template v-slot:content>
            <li>
              <router-link
                v-shortkey="['n']"
                :to="{ name: '<%= vue_plural %>-new' }"
                @shortkey.native="$router.push({ name: '<%= vue_plural %>-new' })">
                {{ $t('<%= vue_plural %>.new') }}
              </router-link>
            </li>
          </template>
        </Dropdown>
      </div>
    </div>
    <ContentList
      v-if="<%= vue_plural %>"
      :entries="<%= vue_plural %>"<%= if sequenced do %>
      :sortable="true"
      @sort="sortEntries"<% end %><%= if status do %>
      :status="true"<% end %>
      :filter-keys="['<%= main_field %>']"
      @updateQuery="queryVars = $event">

      <template v-slot:selected="{ entries, clearSelection }">
        <li>
          <button
            @click="deleteEntries(entries, clearSelection)">
            {{ $t('<%= vue_plural %>.delete-entries') }}
          </button>
        </li>
      </template>

      <template v-slot:row="{ entry }">
        <%= for {_, v} <- vue_contentlist_rows do %><%= v %>
        <% end %>
        <%= if creator do %><div class="col-3">
          <ItemMeta
            :entry="entry"
            :user="entry.creator" />
        </div><% end %>

        <div class="col-1">
          <CircleDropdown>
            <li>
              <router-link :to="{ name: '<%= vue_plural %>-edit', params: { <%= vue_singular %>Id: entry.id } }">
                {{ $t('<%= vue_plural %>.edit') }}
              </router-link>
            </li>
            <li>
              <button
                @click="deleteEntry(entry.id)">
                {{ $t('<%= vue_plural %>.delete') }}
              </button>
            </li>
          </CircleDropdown>
        </div>
      </template>
    </ContentList>
  </article>
</template>

<script>

import gql from 'graphql-tag'
import GET_<%= String.upcase(plural) %> from '../../gql/<%= snake_domain %>/<%= String.upcase(plural) %>_QUERY.graphql'
import locale from '../../locales/<%= vue_plural %>'

export default {
  data () {
    return {
      queryVars: {
        filter: null,
        offset: 0,
        limit: 50<%= if status do %>,
        status: 'all'<% end %>
      },
      page: 0,
      // if the entries has children, enable this
      // and call ChildrenButton with :visible-children="visibleChildren".
      // You can then query the child list for visibility with this.
      // See PageListView in BrandoJS for more info
      // visibleChildren: []
    }
  },

  inject: [
    'adminChannel'
  ],

  methods: {
    <%= if sequenced do %>sortEntries (seq) {
      this.adminChannel.channel
        .push('<%= vue_plural %>:sequence_<%= vue_plural %>', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('<%= vue_plural %>.sequence-updated') })
        })
    },
    <% end %>
    deleteEntries (entries, clearSelection) {
      this.$alerts.alertConfirm('OBS', this.$t('<%= vue_plural %>.delete-confirm-many'), async data => {
        if (!data) {
          return
        }

        entries.forEach(async id => {
          this.deleteEntry(id, true)
        })

        clearSelection()
      })
    },

    async deleteEntry (entryId, override = false) {
      const fn = async () => {
        try {
          await this.$apollo.mutate({
            mutation: gql`
              mutation Delete<%= Recase.to_pascal(vue_singular) %>($<%= vue_singular %>Id: ID!) {
                delete<%= Recase.to_pascal(vue_singular) %>(
                  <%= vue_singular %>Id: $<%= vue_singular %>Id,
                ) {
                  id
                }
              }
            `,
            variables: {
              <%= vue_singular %>Id: parseInt(entryId)
            },

            update: (store, { data: { delete<%= Recase.to_pascal(vue_singular) %> } }) => {
              this.$apollo.queries.<%= vue_plural %>.refresh()
            }
          })

          this.$toast.success({ message: this.$t('<%= vue_plural %>.deleted') })
        } catch (err) {
          this.$utils.showError(err)
        }
      }

      if (override) {
        fn()
      } else {
        this.$alerts.alertConfirm('OBS', this.$t('<%= vue_plural %>.delete-confirm'), async confirm => {
          if (!confirm) {
            return false
          } else {
            fn()
          }
        })
      }
    }
  },

  apollo: {
    <%= vue_plural %>: {
      query: GET_<%= String.upcase(plural) %>,
      variables () {
        return this.queryVars
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
