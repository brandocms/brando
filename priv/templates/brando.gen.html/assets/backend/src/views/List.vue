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
          Help text
        </p>
      </template>
    </ContentHeader>

    <div class="row">
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
                :to="{ name: '<%= vue_plural %>-new' }">
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
      @sort="sortEntries"<% end %>
      :filter-keys="['title']"
      @filter="queryVars.filter = $event"
      @more="showMore">

      <template v-slot:selected="{ entries, clearSelection }">
        <li>
          <button
            @click="deleteEntries(entries, clearSelection)">
            {{ $t('<%= vue_plural %>.delete-entries') }}
          </button>
        </li>
      </template>

      <template v-slot:row="{ entry }">
        <%= for {_, v} <- list_rows do %><%= v %>
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

export default {
  data () {
    return {
      queryVars: {
        filter: null,
        offset: 0,
        limit: 25
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
    showMore () {
      this.page++
      // Fetch more data and transform the original result
      this.$apollo.queries.<%= vue_plural %>.fetchMore({
        // New variables
        variables: {
          limit: this.queryVars.limit,
          offset: this.page * 25,
          filter: this.queryVars.filter
        },
        // Transform the previous result with new data
        updateQuery: (previousResult, { fetchMoreResult }) => {
          const newEntries = fetchMoreResult.<%= vue_plural %>
          // const hasMore = true

          return {
            <%= vue_plural %>: [
              ...previousResult.<%= vue_plural %>, ...newEntries
            ]
          }
        }
      })
    },

    <%= if sequenced do %>sortEntries (seq) {
      this.adminChannel.channel
        .push('<%= vue_plural %>:sequence_<%= vue_plural %>', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('<%= vue_plural %>.sequence-updated') })

          const query = {
            query: GET_<%= String.upcase(plural) %>,
            variables: { ...this.queryVars }
          }
          const store = this.$apolloProvider.defaultClient.store.cache
          const data = store.readQuery(query)

          data.<%= vue_plural %>.sort((a, b) => {
            return seq.indexOf(parseInt(a.id)) - seq.indexOf(parseInt(b.id))
          })

          store.writeQuery({
            ...query,
            data
          })
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
              try {
                const query = {
                  query: GET_<%= String.upcase(plural) %>,
                  variables: { ...this.queryVars }
                }
                const data = store.readQuery(query)
                const idx = data.<%= vue_plural %>.findIndex(<%= vue_singular %> => parseInt(<%= vue_singular %>.id) === parseInt(entryId))

                if (idx !== -1) {
                  data.<%= vue_plural %>.splice(idx, 1)

                  // Write back to the cache
                  store.writeQuery({
                    ...query,
                    data
                  })
                }
              } catch (e) {
                console.log(e)
                // ignore errors. usually means it's just not in cache.
              }
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
      debounce: 750,
      variables () {
        return {
          limit: this.queryVars.limit,
          offset: this.queryVars.offset,
          filter: this.queryVars.filter
        }
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
</style>

<i18n>
{
  "en": {
    "<%= vue_plural %>.edit": "Edit entry",
    "<%= vue_plural %>.delete": "Delete entry",
    "<%= vue_plural %>.title": "<%= Recase.SentenceCase.convert(plural) %>",
    "<%= vue_plural %>.subtitle": "Administration",
    "<%= vue_plural %>.index": "Index",
    "<%= vue_plural %>.actions": "Actions",
    "<%= vue_plural %>.new": "New entry",
    "<%= vue_plural %>.sequence_updated": "Sequence updated",
    "<%= vue_plural %>.deleted": "Entry deleted",
    "<%= vue_plural %>.delete-entries": "Delete entries",
    "<%= vue_plural %>.delete-confirm": "Are you sure you want to delete this?",
    "<%= vue_plural %>.delete-confirm-many": "Are you sure you want to delete these entries?",
    "<%= vue_plural %>.sequence-updated": "Sequence updated",
    "<%= vue_plural %>.more": "More"
  },
  "nb": {
    "<%= vue_plural %>.edit": "Rediger objekt",
    "<%= vue_plural %>.delete": "Slett objekt",
    "<%= vue_plural %>.title": "<%= Recase.SentenceCase.convert(plural) %>",
    "<%= vue_plural %>.subtitle": "Administrasjon",
    "<%= vue_plural %>.index": "Oversikt",
    "<%= vue_plural %>.actions": "Handlinger",
    "<%= vue_plural %>.new": "Nytt objekt",
    "<%= vue_plural %>.sequence_updated": "Rekkefølgen ble oppdatert",
    "<%= vue_plural %>.deleted": "Objektet ble slettet",
    "<%= vue_plural %>.delete-entries": "Slett objekter",
    "<%= vue_plural %>.delete-confirm": "Er du sikker på at du vil slette dette?",
    "<%= vue_plural %>.delete-confirm-many": "Er du sikker på at du vil slette disse?",
    "<%= vue_plural %>.sequence-updated": "Rekkefølge oppdatert",
    "<%= vue_plural %>.more": "Mer"
  }
}
</i18n>
