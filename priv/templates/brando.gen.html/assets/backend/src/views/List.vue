<template>
  <spinner :overlay="true" :transparent="true" v-if="loading" />
  <div class="<%= plural %> container" v-else appear>
    <div class="row">
      <div class="col-md-12">
        <div class="card">
          <div class="card-header">
            <h5 class="section mb-0">Oversikt</h5>
          </div>
          <div class="card-body">
            <div class="jumbotron text-center">
              <h1 class="display-1 text-uppercase text-strong">Deltittel</h1>
              <p class="lead">Kort om delsiden</p>
              <hr class="my-4">
              <p class="lead">
                <router-link
                  :to="{ name: '<%= singular %>-new' }"
                  class="btn btn-secondary"
                  exact>
                  Ny <%= vue_singular %>
                </router-link>
              </p>
            </div>

            <table
              v-if="all<%= Recase.to_pascal(vue_plural) %>.length"
              class="table table-airy">
              <tbody
                name="slide-fade-top-slow"<%= if sequenced do %>
                v-sortable="{handle: 'tr', animation: 250, store: {get: getOrder, set: storeOrder}}"<% end %>
                is="transition-group">
                <%= if sequenced do %>
                <tr
                  v-for="<%= vue_singular %> in all<%= Recase.to_pascal(vue_plural) %>"
                  :key="<%= vue_singular %>.id"
                  :data-id="<%= vue_singular %>.id">
                  <td class="fit">
                    <i class="fal fa-fw fa-arrows-v"></i>
                  </td>
                <% else %>
                <tr
                  v-for="<%= vue_singular %> in all<%= Recase.to_pascal(vue_plural) %>"
                  :key="<%= vue_singular %>.id">
                <% end %>
                  <%= for {_, v} <- list_rows do %>
                    <%= v %>
                  <% end %>
                  <td
                    v-if="['superuser'].includes(me.role)"
                    class="text-center fit">
                    <b-dropdown variant="white" no-caret>
                      <template slot="button-content">
                        <i class="k-dropdown-icon"></i>
                      </template>
                      <router-link
                        :to="{ name: '<%= singular %>-edit', params: { <%= vue_singular %>Id: <%= vue_singular %>.id } }"
                        tag="button"
                        :class="{'dropdown-item': true}"
                        exact
                      >
                        <i class="fal fa-pencil fa-fw mr-4"></i>
                        Endre
                      </router-link>
                      <button @click.prevent="delete<%= Recase.to_pascal(vue_singular) %>(<%= vue_singular %>)" class="dropdown-item">
                        <i class="fal fa-fw fa-trash-alt mr-4"></i>Slett
                      </button>
                    </b-dropdown>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { mapActions, mapGetters } from 'kurtz/vuex'

export default {
  components: {
  },

  data () {
    return {
      loading: 0,
      sorted<%= Recase.to_pascal(vue_singular) %>Ids: []<%= if gallery do %>,
      showImageSeriesModal: null,
      selectedImages: []<% end %>
    }
  },

  computed: {
    ...mapGetters('users', [
      'me'
    ]),
    ...mapGetters('<%= vue_plural %>', [
      'all<%= Recase.to_pascal(vue_plural) %>'
    ])
  },

  inject: [
    'adminChannel'
  ],

  async created () {
    console.debug('created <<%= Recase.to_pascal(vue_singular) %>ListView />')
    this.loading++
    await this.get<%= Recase.to_pascal(vue_plural) %>()
    this.loading--
  },

  methods: {
    getOrder (sortable) {
      return this.all<%= Recase.to_pascal(vue_plural) %>
    },

    storeOrder (sortable) {
      this.sorted<%= Recase.to_pascal(vue_singular) %>Ids = sortable.toArray()
      this.adminChannel.channel
        .push('<%= plural %>:sequence_<%= plural %>', { ids: this.sorted<%= Recase.to_pascal(vue_singular) %>Ids })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Rekkefølge lagret' })
        })
    },
    <%= if gallery do %>
    createImageSeries (id) {
      this.adminChannel.channel
        .push('<%= singular %>:create_image_series', { <%= singular %>_id: id })
        .receive('ok', payload => {
          this.addImageSeriesTo<%= Recase.to_pascal(vue_singular) %>({ <%= singular %>Id: id, imageSeries: payload.image_series })
        })
    },

    openImageSeriesModal (id) {
      this.showImageSeriesModal = id
    },

    closeImageSeriesModal () {
      this.showImageSeriesModal = null
    },
    <% end %>
    ...mapActions('<%= vue_plural %>', [
      'get<%= Recase.to_pascal(vue_plural) %>',
      'delete<%= Recase.to_pascal(vue_singular) %>'<%= if gallery do %>,
      'addImageSeriesTo<%= Recase.to_pascal(vue_singular) %>'<% end %>
    ])
  }
}
</script>
