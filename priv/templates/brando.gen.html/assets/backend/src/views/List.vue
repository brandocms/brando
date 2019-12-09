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
          {{ $t('<%= vue_plural %>.index')}}
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
      @sort="sortPages"<% end %>>

      <template v-slot:row="{ entry }">
        <%= for {_, v} <- list_rows do %><%= v %>
        <% end %>
        <div class="col-3">
          <ItemMeta
            :entry="entry"
            :user="entry.creator" />
        </div>

        <div class="col-1">
          <CircleDropdown>
            <li>
              <router-link :to="{ name: '<%= vue_plural %>-edit', params: { <%= vue_singular %>Id: entry.id } }">
                {{$t('<%= vue_plural %>.edit')}}
              </router-link>
            </li>
            <li>
              <button
                @click="del(entry)">
                {{$t('<%= vue_plural %>.delete')}}
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
import GET_<%= String.upcase(plural) %> from './gql/<%= String.upcase(plural) %>_QUERY.graphql'

export default {
  data () {
    return {
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
    <%= if sequenced do %>    sort (seq) {
      this.adminChannel.channel
        .push('<%= vue_plural %>:sequence_<%= vue_plural %>', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('<%= vue_plural %>.sequence-updated') })

          const query = { query: GET_<%= String.upcase(plural) %> }
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
    },<% end %>
    async del (entry) {
      this.$alerts.alertConfirm('OBS', this.$t('<%= vue_plural %>.delete-confirm'), async confirm => {
        if (!confirm) {
          return false
        } else {
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
                <%= vue_singular %>Id: parseInt(entry.id)
              },

              update: (store, { data: { delete<%= Recase.to_pascal(vue_singular) %> } }) => {
                try {
                  const query = {
                    query: GET_<%= String.upcase(plural) %>
                  }
                  const data = store.readQuery(query)
                  const idx = data.<%= vue_plural %>.findIndex(<%= vue_singular %> => parseInt(<%= vue_singular %>.id) === parseInt(entry.id))

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
      })
    }
  },

  apollo: {
    <%= vue_plural %>: {
      query: GET_<%= String.upcase(plural) %>
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
    "<%= vue_plural %>.title": "Title",
    "<%= vue_plural %>.subtitle": "Subtitle",
    "<%= vue_plural %>.index": "Index",
    "<%= vue_plural %>.actions": "Actions",
    "<%= vue_plural %>.new": "New entry",
    "<%= vue_plural %>.sequence_updated": "Sequence updated",
    "<%= vue_plural %>.deleted": "Entry deleted",
    "<%= vue_plural %>.delete-confirm": "Are you sure you want to delete this?",
    "<%= vue_plural %>.sequence-updated": "Sequence updated"
  },
  "nb": {
    "<%= vue_plural %>.edit": "Rediger objekt",
    "<%= vue_plural %>.delete": "Slett objekt",
    "<%= vue_plural %>.title": "Tittel",
    "<%= vue_plural %>.subtitle": "Undertittel",
    "<%= vue_plural %>.index": "Oversikt",
    "<%= vue_plural %>.actions": "Handlinger",
    "<%= vue_plural %>.new": "Nytt objekt",
    "<%= vue_plural %>.sequence_updated": "Rekkefølgen ble oppdatert",
    "<%= vue_plural %>.deleted": "Objektet ble slettet",
    "<%= vue_plural %>.delete-confirm": "Er du sikker på at du vil slette dette?",
    "<%= vue_plural %>.sequence-updated": "Rekkefølge oppdatert"
  }
}
</i18n>
