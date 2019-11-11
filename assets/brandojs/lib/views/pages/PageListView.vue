<template>
  <div
    v-if="!loading"
    class="pages container"
    appear>
    <div class="row">
      <div class="col-md-12">
        <div class="card">
          <div class="card-header">
            <h5 class="section mb-0">
              Sider
            </h5>
          </div>
          <div class="card-body">
            <div class="jumbotron text-center">
              <h1 class="display-1 text-uppercase text-strong">
                Sider
              </h1>
              <p class="lead">
                Administrér sideinnhold og fragmenter
              </p>
              <hr class="my-4">
              <p class="lead">
                <router-link
                  :to="{ name: 'page-create' }"
                  class="btn btn-secondary"
                  exact>
                  Ny side
                </router-link>
                <br>
                <button
                  v-b-popover.hover.bottom="'Brukes kun ved manuelle backend-endringer!'"
                  class="btn btn-danger mt-2"
                  @click.prevent="rerenderPagesAndFragments()">
                  (!) Reprosessér alle sider og fragmenter
                </button>
              </p>
            </div>

            <div class="page-list">
              <table class="table table-airy">
                <transition-group
                  v-sortable="{handle: '.page-sort-handle', animation: 0, store: {get: getOrder, set: storeOrder}}"
                  name="fade-move"
                  tag="div"
                  class="sort-container flex-column">
                  <tbody
                    v-for="page in allPages"
                    :key="'page'+page.id"
                    :data-id="page.id">
                    <tr>
                      <td class="fit page-sort-handle">
                        <i class="fal fa-fw fa-arrows-v"></i>
                      </td>
                      <td class="fit">
                        <Flag :value="page.language" />
                      </td>
                      <td
                        class="text-mono text-sm text-left fit"
                        style="min-width: 100px">
                        {{ page.key }}
                      </td>
                      <td
                        class="fit"
                        style="min-width: 150px">
                        <span
                          v-if="page.fragments && page.fragments.length > 0 && !pageFragmentsShown.includes(page.id)"
                          v-b-popover.hover.top="'Vis sidens fragmenter'"
                          class="badge badge-outline-primary badge-sm text-uppercase"
                          style="cursor: pointer;"
                          @click="showFragmentsFor(page.id)">
                          + <strong>{{ page.fragments.length }}</strong> fragmenter
                        </span>
                        <span
                          v-else-if="pageFragmentsShown.includes(page.id) && page.fragments.length > 0"
                          class="badge badge-outline-primary badge-sm text-uppercase"
                          style="cursor: pointer;"
                          @click="hideFragmentsFor(page.id)">
                          - <strong>{{ page.fragments.length }}</strong> fragmenter
                        </span>
                      </td>
                      <td class="text-sm text-strong">
                        <router-link
                          v-b-popover.hover.top="'Vis sidens hovedmal'"
                          :to="{ name: 'page-edit', params: { pageId: page.id } }"
                          exact>
                          {{ page.title }}
                        </router-link>
                      </td>

                      <td class="text-xs fit">
                        {{ page.updated_at | datetime }}
                      </td>
                      <td class="fit">
                        <b-dropdown
                          variant="white"
                          no-caret>
                          <template slot="button-content">
                            <i class="k-dropdown-icon" />
                          </template>
                          <template v-slot:default="{ hide }">
                            <router-link
                              :to="{ name: 'page-edit', params: { pageId: page.id } }"
                              :class="{'dropdown-item': true}"
                              tag="button"
                              exact>
                              <i class="fal fa-pencil fa-fw mr-2" />
                              Endre side
                            </router-link>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="rerenderPage(page); hide()">
                              <i class="fal fa-sync fa-fw mr-2" />
                              Reprosessér side
                            </button>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="duplicatePage(page); hide()">
                              <i class="fal fa-copy fa-fw mr-2" />
                              Duplisér side
                            </button>
                            <router-link
                              :to="{ name: 'pagefragment-create', params: { pageId: page.id } }"
                              :class="{'dropdown-item': true}"
                              tag="button"
                              exact>
                              <i class="fal fa-star fa-fw mr-2" />
                              Opprett fragment
                            </router-link>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="deletePage(page)">
                              <i class="fal fa-trash fa-fw mr-2" />
                              Slett side
                            </button>
                          </template>
                        </b-dropdown>
                      </td>
                    </tr>
                    <tr
                      v-for="fragment in page.fragments"
                      v-if="shouldShowFragments(page.id)"
                      :key="fragment.id"
                      :data-id="fragment.id"
                      class="page-subrow">
                      <td class="fit" />
                      <td class="fit" />
                      <td class="fit" />
                      <td class="fit text-center">
                        ↳
                      </td>
                      <td class="text-sm text-strong">
                        <router-link
                          class="plain"
                          :to="{ name: 'pagefragment-edit', params: { pageId: fragment.id } }"
                          exact>
                          <code>{{ fragment.parent_key }}</code> <span class="ml-3 mr-3">&rarr;</span> <span class="badge badge-outline-primary badge-sm text-uppercase">{{ fragment.key }}</span>
                        </router-link>
                      </td>
                      <td class="fit text-xs">
                        {{ fragment.updated_at | datetime }}
                      </td>
                      <td>
                        <b-dropdown
                          variant="white"
                          no-caret>
                          <template slot="button-content">
                            <i class="k-dropdown-icon" />
                          </template>
                          <template v-slot:default="{ hide }">
                            <router-link
                              :to="{ name: 'pagefragment-edit', params: { pageId: fragment.id } }"
                              :class="{'dropdown-item': true}"
                              tag="button"
                              exact>
                              <i class="fal fa-pencil fa-fw mr-2" />
                              Endre fragment
                            </router-link>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="duplicatePageFragment(fragment, page.id); hide()">
                              <i class="fal fa-copy fa-fw mr-2" />
                              Duplisér fragment
                            </button>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="rerenderPageFragment(fragment); hide()">
                              <i class="fal fa-sync fa-fw mr-2" />
                              Reprosessér fragment
                            </button>
                            <button
                              :class="{'dropdown-item': true}"
                              @click.prevent="deletePageFragment(fragment)">
                              <i class="fal fa-trash fa-fw mr-2" />
                              Slett fragment
                            </button>
                          </template>
                        </b-dropdown>
                      </td>
                    </tr>
                    <tr
                      v-for="subpage in page.children"
                      :key="subpage.id"
                      class="page-subrow">
                      <td class="">
                        <i class="fa fa-fw fa-angle-double-right" />
                      </td>
                      <td class="fit">
                        <Flag :value="subpage.language" />
                      </td>
                      <td class="text-mono text-sm text-left fit">
                        {{ page.key }} / {{ subpage.key }}
                      </td>
                      <td class="text-sm text-strong">
                        <router-link
                          :to="{ name: 'page-edit', params: { pageId: subpage.id } }"
                          exact>
                          {{ subpage.title }}
                        </router-link>
                      </td>
                      <td class="fit text-xs">
                        {{ subpage.updated_at | datetime }}
                      </td>
                      <td>
                        <b-dropdown
                          variant="white"
                          no-caret>
                          <template slot="button-content">
                            <i class="k-dropdown-icon" />
                          </template>
                          <router-link
                            :to="{ name: 'page-edit', params: { subpageId: subpage.id } }"
                            :class="{'dropdown-item': true}"
                            tag="button"
                            exact>
                            <i class="fal fa-pencil fa-fw mr-2" />
                            Endre subpage
                          </router-link>
                          <button
                            :class="{'dropdown-item': true}"
                            @click.prevent="deletePage(subpage)">
                            <i class="fal fa-trash fa-fw mr-2" />
                            Slett subpage
                          </button>
                        </b-dropdown>
                      </td>
                    </tr>
                  </tbody>
                </transition-group>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { mapActions, mapGetters } from 'vuex'
import { alertConfirm } from 'brandojs/lib/utils/alerts'
import { pageFragmentAPI } from 'brandojs/lib/api/pageFragment'

export default {
  components: {

  },

  data () {
    return {
      loading: 0,
      pageFragmentsShown: [],
      sortedPageIds: []
    }
  },

  computed: {
    ...mapGetters('users', [
      'me'
    ]),
    ...mapGetters('pages', [
      'allPages'
    ])
  },

  inject: [
    'adminChannel'
  ],

  created () {
    console.debug('created <PageListView />')
    this.getData()
  },

  methods: {
    getOrder (sortable) {
      return this.allPages
    },

    storeOrder (sortable) {
      this.sortedPagesIds = sortable.toArray()
      this.adminChannel.channel
        .push('pages:sequence_pages', { ids: this.sortedPagesIds })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Rekkefølge lagret' })
        })
    },

    shouldShowFragments (pageId) {
      if (this.pageFragmentsShown.includes(pageId)) {
        return true
      }
      return false
    },

    showFragmentsFor (pageId) {
      this.pageFragmentsShown.push(pageId)
    },

    hideFragmentsFor (pageId) {
      this.pageFragmentsShown = this.pageFragmentsShown.filter(function (value, index, arr) {
        return value > pageId
      })
    },

    async getData () {
      this.loading++
      await this.getPages()
      this.loading--
    },

    duplicatePage (page) {
      this.adminChannel.channel
        .push('page:duplicate', { id: page.id })
        .receive('ok', payload => {
          this.$store.commit('pages/ADD_PAGE', payload.page)
        })
    },

    rerenderPage (page) {
      this.adminChannel.channel
        .push('page:rerender', { id: page.id })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Siden ble gjengitt på nytt' })
        })
    },

    rerenderPagesAndFragments () {
      this.rerenderPages()
      this.rerenderPageFragments()
    },

    rerenderPages () {
      alertConfirm('OBS', 'Er du sikker på at du vil gjengi ALLE sider på nytt?', async (data) => {
        if (!data) {
          return
        }
        this.adminChannel.channel
          .push('page:rerender_all')
          .receive('ok', payload => {
            this.$toast.success({ message: 'Sidene ble gjengitt på nytt' })
          })
      })
    },

    deletePage (page) {
      alertConfirm('OBS', 'Er du sikker på at du vil slette denne siden?', (data) => {
        if (!data) {
          return
        }

        this.adminChannel.channel
          .push('page:delete', { id: page.id })
          .receive('ok', payload => {
            this.$store.commit('pages/DELETE_PAGE', page.id)
            this.$toast.success({ message: 'Siden ble slettet' })
          })
      })
    },

    duplicatePageFragment (srcFragment, pageId) {
      this.adminChannel.channel
        .push('page_fragment:duplicate', { id: srcFragment.id })
        .receive('ok', payload => {
          this.$store.commit('pages/ADD_PAGE_FRAGMENT', { pageFragment: payload.page_fragment, pageId: pageId })
        })
    },

    rerenderPageFragment (page) {
      this.adminChannel.channel
        .push('page_fragment:rerender', { id: page.id })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Fragmentet ble gjengitt på nytt' })
        })
    },

    rerenderPageFragments () {
      alertConfirm('OBS', 'Er du sikker på at du vil gjengi ALLE fragmenter på nytt?', async (data) => {
        if (!data) {
          return
        }
        this.adminChannel.channel
          .push('page_fragment:rerender_all')
          .receive('ok', payload => {
            this.$toast.success({ message: 'Fragmentene ble gjengitt på nytt' })
          })
      })
    },

    deletePageFragment (page) {
      alertConfirm('OBS', 'Er du sikker på at du vil slette dette fragmentet?', async (data) => {
        if (!data) {
          return
        }

        await pageFragmentAPI.deletePageFragment(page.id)
        this.$store.commit('pages/DELETE_PAGE_FRAGMENT', { pageFragmentId: page.id, pageId: page.page_id })
        this.$toast.success({ message: 'Fragmentet ble slettet' })
      })
    },

    ...mapActions('pages', [
      'getPages'
    ])
  }
}
</script>
