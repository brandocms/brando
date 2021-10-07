<template>
  <article>
    <ContentHeader>
      <template #title>
        {{ $t('pages.title') }}
      </template>
      <template #subtitle>
        {{ $t('pages.subtitle') }}
      </template>
      <template #help>
        <div>
          <Dropdown>
            <template #default>
              {{ $t('pages.actions') }}
            </template>
            <template #content>
              <li>
                <router-link :to="{ name: 'pages-new' }">
                  {{ $t('pages.new') }}
                </router-link>
              </li>
              <li>
                <button
                  type="button"
                  @click="rerender">
                  {{ $t('pages.rerender') }}
                </button>
              </li>
            </template>
          </Dropdown>
        </div>
      </template>
    </ContentHeader>

    <div class="row">
      <div class="half">
        <h2>{{ $t('pages.index') }}</h2>
      </div>
    </div>

    <ContentList
      v-if="pages"
      :entries="pages"
      :sortable="true"
      :status="true"
      :filter-keys="['title']"
      @updateQuery="queryVars = $event"
      @sort="sortPages">
      <template #selected="{ entries, clearSelection}">
        <li>
          <button
            @click="deleteEntries(entries, clearSelection)">
            {{ $t('pages.delete-pages') }}
          </button>
        </li>
      </template>
      <template #row="{ entry }">
        <div class="col-1">
          <CircleFlag :language="entry.language" />
        </div>
        <div class="col-7 title">
          <FontAwesomeIcon
            v-if="entry.isHomepage"
            class="mr-1"
            size="xs"
            icon="home" /><router-link
              :to="{ name: 'pages-edit', params: { pageId: entry.id } }"
              class="link name-link">
              {{ entry.title }}
            </router-link><br>
          <div class="badge">
            <FontAwesomeIcon
              icon="globe-americas"
              size="sm" /> {{ entry.uri }}
          </div>
        </div>
        <div class="col-2 justify-end">
          <ChildrenButton
            v-show="(entry.fragments ? entry.fragments.length : 0) + (entry.children ? entry.children.length : 0)"
            :id="entry.id"
            :length="(entry.fragments ? entry.fragments.length : 0) + (entry.children ? entry.children.length : 0)"
            :visible-children="visibleChildren">
          </ChildrenButton>
        </div>
        <div class="col-4">
          <ItemMeta
            :entry="entry"
            :user="entry.creator" />
        </div>
        <div class="col-1">
          <CircleDropdown>
            <li>
              <router-link
                :to="{ name: 'pages-edit', params: { pageId: entry.id } }">
                {{ $t('pages.edit-page') }}
              </router-link>
            </li>
            <li>
              <router-link
                :to="{ name: 'sections-new', params: { pageId: entry.id } }">
                {{ $t('pages.new-section') }}
              </router-link>
            </li>
            <li>
              <router-link
                :to="{ name: 'pages-new', params: { pageId: entry.id } }">
                {{ $t('pages.new-subpage') }}
              </router-link>
            </li>

            <li>
              <button
                type="button"
                @click="duplicatePage(entry)">
                {{ $t('pages.duplicate-page') }}
              </button>
            </li>

            <li>
              <button
                type="button"
                @click="rerenderPage(entry.id)">
                {{ $t('pages.rerender-page') }}
              </button>
            </li>

            <li>
              <button
                type="button"
                @click="deleteEntry(entry.id)">
                {{ $t('pages.delete-page') }}
              </button>
            </li>
          </CircleDropdown>
        </div>
      </template>
      <template #children="{ entry }">
        <template v-if="visibleChildren.includes(entry.id)">
          <ContentList
            v-if="entry.fragments.length"
            :level="2"
            :entries="entry.fragments"
            :sortable="true"
            :sort-parent="entry.id"
            sequence-handle="section-sequence-handle"
            @sort="sortSections($event, entry.id)"
            @move="moveSections">
            <template #row="{ entry: section }">
              <div class="col-1">
                <div class="arrow">
                  ↳
                </div>
              </div>
              <div class="col-1">
                <CircleFlag :language="section.language" />
              </div>
              <div class="col-6 subtitle">
                <div class="flex-v">
                  <router-link
                    :to="{ name: 'sections-edit', params: { sectionId: section.id } }">
                    {{ section.title || $t('pages.no-title') }}
                  </router-link>
                  <div class="keys">
                    <div class="badge">
                      <FontAwesomeIcon
                        icon="key"
                        size="sm" /> {{ section.parentKey }}/<strong>{{ section.key }}</strong>
                    </div>
                  </div>
                </div>
              </div>
              <div class="col-2 justify-end">
                <div class="badge">
                  {{ $t('pages.section') }}
                </div>
              </div>
              <div class="col-4">
                <ItemMeta
                  :entry="section"
                  :user="section.creator" />
              </div>
              <div class="col-1">
                <CircleDropdown>
                  <li>
                    <router-link
                      :to="{ name: 'sections-edit', params: { sectionId: section.id } }">
                      {{ $t('pages.edit-section') }}
                    </router-link>
                  </li>

                  <li>
                    <button
                      type="button"
                      @click="duplicateSection(section)">
                      {{ $t('pages.duplicate-section') }}
                    </button>
                  </li>

                  <li>
                    <button
                      type="button"
                      @click="rerenderSection(section.id)">
                      {{ $t('pages.rerender-section') }}
                    </button>
                  </li>

                  <li>
                    <button @click="deleteSection(section)">
                      {{ $t('pages.delete-section') }}
                    </button>
                  </li>
                </CircleDropdown>
              </div>
            </template>
          </ContentList>
          <ContentList
            v-if="entry.children.length"
            :level="2"
            :entries="entry.children">
            <template #row="{ entry: subPage }">
              <div class="col-1">
              </div>
              <div class="col-1">
                <div class="arrow">
                  ↳
                </div>
              </div>
              <div class="col-1">
                <CircleFlag :language="subPage.language" />
              </div>
              <div class="col-6 title flex-v">
                <router-link :to="{ name: 'pages-edit', params: { pageId: subPage.id } }">
                  {{ subPage.title }}
                </router-link>
                <div class="badge">
                  <FontAwesomeIcon
                    icon="globe-americas"
                    size="sm" /> {{ subPage.uri }}
                </div>
              </div>
              <div class="col-2 justify-end">
                <ChildrenButton
                  v-show="(subPage.fragments ? subPage.fragments.length : 0) + (subPage.children ? subPage.children.length : 0)"
                  :id="subPage.id"
                  :length="(subPage.fragments ? subPage.fragments.length : 0) + (subPage.children ? subPage.children.length : 0)"
                  :visible-children="visibleChildrenSubPages">
                </ChildrenButton>
              </div>
              <div class="col-4">
                <ItemMeta
                  :entry="subPage"
                  :user="subPage.creator" />
              </div>
              <div class="col-1">
                <CircleDropdown>
                  <li>
                    <router-link
                      :to="{ name: 'pages-edit', params: { pageId: subPage.id } }">
                      {{ $t('pages.edit-subpage') }}
                    </router-link>
                  </li>
                  <li>
                    <button @click="deleteEntry(subPage.id)">
                      {{ $t('pages.delete-subpage') }}
                    </button>
                  </li>
                  <li>
                    <router-link
                      :to="{ name: 'pages-new', params: { pageId: subPage.id } }">
                      {{ $t('pages.new-subpage') }}
                    </router-link>
                  </li>
                </CircleDropdown>
              </div>
            </template>
            <template #children="{ entry: subPage }">
              <template v-if="visibleChildrenSubPages.includes(subPage.id)">
                <ContentList
                  v-if="subPage.children.length"
                  :level="2"
                  :entries="subPage.children">
                  <template #row="{ entry: subSubPage }">
                    <div class="col-1">
                    </div>
                    <div class="col-1">
                    </div>
                    <div class="col-1">
                      <div class="arrow">
                        ↳
                      </div>
                    </div>
                    <div class="col-1">
                      <CircleFlag :language="subSubPage.language" />
                    </div>
                    <div class="col-7 title flex-v">
                      <router-link :to="{ name: 'pages-edit', params: { pageId: subSubPage.id } }">
                        {{ subSubPage.title }}
                      </router-link>
                      <div class="badge">
                        <FontAwesomeIcon
                          icon="globe-americas"
                          size="sm" /> {{ subSubPage.uri }}
                      </div>
                    </div>
                    <div class="col-4">
                      <ItemMeta
                        :entry="subSubPage"
                        :user="subSubPage.creator" />
                    </div>
                    <div class="col-1">
                      <CircleDropdown>
                        <li>
                          <router-link
                            :to="{ name: 'pages-edit', params: { pageId: subSubPage.id } }">
                            {{ $t('pages.edit-subpage') }}
                          </router-link>
                        </li>
                        <li>
                          <button @click="deleteEntry(subSubPage.id)">
                            {{ $t('pages.delete-subpage') }}
                          </button>
                        </li>
                      </CircleDropdown>
                    </div>
                  </template>
                </ContentList>
              </template>
            </template>
          </ContentList>
        </template>
      </template>
    </ContentList>
  </article>
</template>

<script>
import gql from 'graphql-tag'
import GET_PAGES from '../../gql/pages/PAGES_QUERY.graphql'
import locale from '../../locales/pages'
// import Blueprint from '../../mixins/Blueprint'

export default {
  // mixins: [
  //   Blueprint({ blueprint: 'Brando.Blueprints.Pages.Page' })
  // ],

  inject: ['adminChannel'],

  data () {
    return {
      visibleChildren: [],
      visibleChildrenSubPages: [],
      queryVars: {
        filter: {parents: true},
        offset: 0,
        limit: 50,
        status: 'all'
      }
    }
  },

  methods: {
    rerender () {
      this.adminChannel.channel
        .push('page:rerender_all', {})
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.pages-rerendered') })
        })

      this.adminChannel.channel
        .push('fragment:rerender_all', {})
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.fragments-rerendered') })
        })
    },

    rerenderPage (id) {
      this.adminChannel.channel
        .push('page:rerender', { id })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.page-rerendered') })
        })
    },

    rerenderSection (id) {
      this.adminChannel.channel
        .push('fragment:rerender', { id })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.section-rerendered') })
        })
    },

    sortPages (seq) {
      this.adminChannel.channel
        .push('pages:sequence_pages', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.sequence-updated') })
        })
    },

    sortSections (seq, pageId) {
      this.adminChannel.channel
        .push('fragments:sequence_fragments', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.sequence-updated') })
        })
    },

    moveSections (data) {
      // TODO!: move sections
    },

    async duplicatePage (page) {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation DuplicatePage($id: ID!) {
              duplicatePage(id: $id) {
                id
              }
            }
          `,
          variables: {
            id: page.id
          }
        })

        this.$toast.success({ message: this.$t('pages.page-duplicated') })
        this.$apollo.queries.pages.refresh()
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    async duplicateSection (section) {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation DuplicateSection($id: ID!) {
              duplicateSection(id: $id) {
                id
              }
            }
          `,
          variables: {
            id: section.id
          },

          update: (store, { data: { duplicateSection } }) => {
            this.$apollo.queries.pages.refresh()
          }
        })

        this.$toast.success({ message: this.$t('pages.section-duplicated') })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    async deleteSection (section) {
      this.$alerts.alertConfirm(
        'OBS',
        this.$t('pages.are-you-sure-you-want-to-delete-this-section'),
        async confirm => {
          if (!confirm) {
            return false
          } else {
            try {
              await this.$apollo.mutate({
                mutation: gql`
                  mutation DeleteFragment($fragmentId: ID!) {
                    deleteFragment(fragmentId: $fragmentId) {
                      id
                    }
                  }
                `,
                variables: {
                  fragmentId: section.id
                }
              })

              this.$toast.success({
                message: this.$t('pages.section-deleted')
              })
              this.$apollo.queries.pages.refresh()
            } catch (err) {
              this.$utils.showError(err)
            }
          }
        }
      )
    },

    async deleteEntry (entryId, override) {
      const fn = async () => {
        try {
          await this.$apollo.mutate({
            mutation: gql`
              mutation DeletePage($pageId: ID!) {
                deletePage(pageId: $pageId) {
                  id
                }
              }
            `,
            variables: {
              pageId: entryId
            },

            update: (store, { data: { deletePage } }) => {
              this.$apollo.queries.pages.refresh()
            }
          })

          this.$toast.success({ message: this.$t('pages.page-deleted') })
        } catch (err) {
          this.$utils.showError(err)
        }
      }

      if (override) {
        fn()
      } else {
        this.$alerts.alertConfirm('OBS', this.$t('pages.delete-confirm'), async confirm => {
          if (!confirm) {
            return false
          } else {
            fn()
          }
        })
      }
    },

    deleteEntries (entries, clearSelection) {
      this.$alerts.alertConfirm('OBS', this.$t('pages.delete-confirm-many'), async data => {
        if (!data) {
          return
        }

        entries.forEach(async id => {
          this.deleteEntry(id, true)
        })

        clearSelection()
      })
    }
  },

  apollo: {
    pages: {
      query: GET_PAGES,
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
  .title {
    @fontsize base;
  }

  .arrow {
    margin-right: 15px;
    opacity: 0.3;
    text-align: center;
  }

  .subtitle {
    @fontsize base(0.8);
    display: flex;
    flex-direction: row;
  }

  >>> .badge {
    margin-top: 5px;
    text-transform: none !important;
  }

  .text-muted {
    opacity: 0.3;
  }
</style>
