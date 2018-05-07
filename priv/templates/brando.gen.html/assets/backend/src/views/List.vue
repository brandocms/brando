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
                <router-link :to="{ name: '<%= singular %>-new' }" class="btn btn-secondary" exact>
                  Ny <%= singular %>
                </router-link>
              </p>
            </div>

            <table class="table table-airy" v-if="all<%= String.capitalize(plural) %>.length">
              <tbody name="slide-fade-top-slow" is="transition-group">
                <tr :key="<%= singular %>.id" v-for="<%= singular %> in all<%= String.capitalize(plural) %>">
                  <td class="text-strong">
                    <!-- <%= singular %>.field -->
                  </td>

                  <td class="text-xs">
                    {{ <%= singular %>.inserted_at | datetime }}
                  </td>
                  <td class="text-center fit" v-if="['superuser'].includes(me.role)">
                    <b-dropdown variant="white" no-caret>
                      <template slot="button-content">
                        <i class="k-dropdown-icon"></i>
                      </template>
                      <router-link
                        :to="{ name: '<%= singular %>-edit', params: { <%= singular %>Id: <%= singular %>.id } }"
                        tag="button"
                        :class="{'dropdown-item': true}"
                        exact
                      >
                        <i class="fal fa-pencil fa-fw mr-4"></i>
                        Endre
                      </router-link>
                      <button @click.prevent="delete<%= String.capitalize(singular) %>(<%= singular %>)" class="dropdown-item">
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
import { mapActions, mapGetters } from 'vuex'

export default {
  components: {
  },

  data () {
    return {
      loading: 0
    }
  },

  async created () {
    console.debug('created <<%= String.capitalize(singular) %>ListView />')
    this.loading++
    await this.get<%= String.capitalize(plural) %>()
    this.loading--
  },

  computed: {
    ...mapGetters('users', [
      'me'
    ]),
    ...mapGetters('<%= plural %>', [
      'all<%= String.capitalize(plural) %>'
    ])
  },

  inject: [
    'adminChannel'
  ],

  methods: {
    ...mapActions('<%= plural %>', [
      'get<%= String.capitalize(plural) %>',
      'delete<%= String.capitalize(singular) %>'
    ])
  }
}
</script>
