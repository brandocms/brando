<template>
  <article>
    <ContentHeader>
      <template v-slot:title>
        {{ $t('pages.title') }}
      </template>
      <template v-slot:subtitle>
        {{ $t('pages.subtitle')}}
      </template>
      <template v-slot:help>
        <p>
          -
        </p>
      </template>
    </ContentHeader>

    <div class="row">
      <div class="half">
        <h2>
          {{ $t('pages.index') }}
        </h2>
      </div>
      <div class="half">
        <Dropdown>
          <template v-slot:default>
            {{ $t('pages.actions') }}
          </template>
          <template v-slot:content>
            <li>
              <router-link
                :to="{ name: 'pages-new' }">
                {{ $t('pages.new') }}
              </router-link>
            </li>
            <li>
              <button>
                {{ $t('pages.reprocess') }}
              </button>
            </li>
          </template>
        </Dropdown>
      </div>
    </div>
    <ContentList
      v-if="pages"
      :entries="pages"
      :sortable="true"
      @sort="sortPages">

      <template v-slot:row="{ entry }">
        <div class="col-1">
          <div class="circle">
            <span>
              {{ entry.language }}
            </span>
          </div>
        </div>
        <div class="col-7 title flex-v">
          <router-link
            :to="{ name: 'pages-edit', params: { pageId: entry.id } }">
            {{ entry.title }}
          </router-link>
          <div class="badge">
            {{ entry.key }}
          </div>
        </div>
        <div class="col-3">
          <ItemMeta
            :entry="entry"
            :user="entry.creator" />
        </div>
        <div class="col-3">
          <ChildrenButton
            :id="entry.id"
            :length="entry.fragments.length"
            :visible-children="visibleChildren">
            <template>seksjoner</template>
          </ChildrenButton>
        </div>
        <div class="col-1">
          <CircleDropdown>
            <li>
              <router-link :to="{ name: 'sections-new', params: { pageId: entry.id } }">
                {{$t('pages.new-section')}}
              </router-link>
            </li>
            <li>
              <router-link :to="{ name: 'pages-edit', params: { pageId: entry.id } }">
                {{$t('pages.edit-page')}}
              </router-link>
            </li>

            <li>
              <router-link :to="{ name: 'dashboard' }">
                {{$t('pages.duplicate-page')}}
              </router-link>
            </li>

            <li>
              <router-link :to="{ name: 'dashboard' }">
                {{$t('pages.reprocess-page')}}
              </router-link>
            </li>

            <li>
              <router-link :to="{ name: 'dashboard' }">
                {{$t('pages.delete-page')}}
              </router-link>
            </li>
          </CircleDropdown>
        </div>
      </template>
      <template v-slot:children="{ entry }">
        <template
          v-if="entry.fragments.length && visibleChildren.includes(entry.id)">
          <ContentList
            :level="2"
            :entries="entry.fragments"
            :sortable="true"
            :sort-parent="entry.id"
            sequence-handle="section-sequence-handle"
            @sort="sortSections($event, entry.id)"
            @move="moveSections">
            <template v-slot:row="{ entry: section }">
              <div class="col-1">
              </div>
              <div class="col-8 subtitle">
                <div class="arrow">↳</div>
                <div class="flex-v">
                  <router-link
                    :to="{ name: 'sections-edit', params: { sectionId: section.id } }">{{ section.title || 'Ingen tittel' }}</router-link>
                  <div class="keys">
                    <div class="badge">
                      {{ section.parent_key }}
                    </div>
                    <div class="badge">
                      {{ section.key }}
                    </div>
                  </div>
                </div>
              </div>
              <div class="col-5 flex-v">
                <div class="badge">
                  {{$t('pages.section')}}
                </div>
              </div>
              <div class="col-1">
                <CircleDropdown>
                  <li>
                    <router-link :to="{ name: 'sections-edit', params: { sectionId: section.id } }">
                      {{$t('pages.edit-section')}}
                    </router-link>
                  </li>
                  <li>
                    <button @click="deleteSection(section)">
                      {{$t('pages.delete-section')}}
                    </button>
                  </li>
                </CircleDropdown>
              </div>
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

export default {
  data () {
    return {
      visibleChildren: []
    }
  },

  inject: [
    'adminChannel'
  ],

  methods: {
    sortPages (seq) {
      this.adminChannel.channel
        .push('pages:sequence_pages', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.sequence-updated') })

          const query = { query: GET_PAGES }
          const store = this.$apolloProvider.defaultClient.store.cache
          const data = store.readQuery(query)

          data.pages.sort((a, b) => {
            return seq.indexOf(parseInt(a.id)) - seq.indexOf(parseInt(b.id))
          })

          store.writeQuery({
            ...query,
            data
          })
        })
    },

    sortSections (seq, pageId) {
      this.adminChannel.channel
        .push('page_fragments:sequence_fragments', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('pages.sequence-updated') })

          const query = { query: GET_PAGES }
          const store = this.$apolloProvider.defaultClient.store.cache
          const data = store.readQuery(query)

          const page = data.pages.find(p => parseInt(p.id) === parseInt(pageId))

          page.fragments.sort((a, b) => {
            return seq.indexOf(parseInt(a.id)) - seq.indexOf(parseInt(b.id))
          })

          store.writeQuery({
            ...query,
            data
          })
        })
    },

    moveSections (data) {
      console.log(data)
    },

    async deleteSection (section) {
      this.$alerts.alertConfirm('OBS', this.$t('pages.are-you-sure-you-want-to-delete-this-section'), async confirm => {
        if (!confirm) {
          return false
        } else {
          try {
            await this.$apollo.mutate({
              mutation: gql`
                mutation DeletePageFragment($pageFragmentId: ID!) {
                  deletePageFragment(
                    pageFragmentId: $pageFragmentId,
                  ) {
                    id
                  }
                }
              `,
              variables: {
                pageFragmentId: section.id
              },

              update: (store, { data: { deletePageFragment } }) => {
                const query = {
                  query: GET_PAGES
                }
                const data = store.readQuery(query)
                const page = data.pages.find(page => parseInt(page.id) === parseInt(section.page_id))

                if (page) {
                  const fragment = page.fragments.find(f => parseInt(f.id) === parseInt(section.id))
                  const idx = page.fragments.indexOf(fragment)

                  page.fragments = [
                    ...page.fragments.slice(0, idx),
                    ...page.fragments.slice(idx + 1)
                  ]

                  // Write back to the cache
                  store.writeQuery({
                    ...query,
                    data
                  })
                } else {
                  console.log('page not found?', data.pages, section.page_id)
                }
              }
            })

            this.$toast.success({ message: this.$t('pages.section-deleted') })
          } catch (err) {
            this.$utils.showError(err)
          }
        }
      })
    }
  },

  apollo: {
    pages: {
      query: GET_PAGES
    }
  }
}
</script>

<style lang="postcss" scoped>
  .title {
    @fontsize base(0.8);
    font-family: theme(typography.families.mono);

    .badge {
      margin-top: 5px;
    }
  }

  .arrow {
    margin-right: 15px;
    opacity: 0.3;
  }

  .subtitle {
    @fontsize base(0.8);
    font-family: theme(typography.families.mono);
    display: flex;
    flex-direction: row;

    .badge {
      margin-top: 5px;
    }
  }
</style>

<i18n>
{
  "en": {
    "pages.title": "Pages and sections",
    "pages.subtitle": "Content administration",
    "pages.index": "Index",
    "pages.actions": "Actions",
    "pages.new": "New page",
    "pages.reprocess": "Reprocess pages/sections",
    "pages.new-section": "New section",
    "pages.section": "Section",
    "pages.sequence-updated": "Sequence updated",
    "pages.delete-page": "Delete page",
    "pages.duplicate-page": "Duplicate page",
    "pages.edit-section": "Edit section",
    "pages.delete-section": "Delete section",
    "pages.are-you-sure-you-want-to-delete-this-section": "Are you sure you want to delete this section?",
    "pages.edit-page": "Edit page",
    "pages.reprocess-page": "Reprocess page",
    "pages.section-deleted": "Section deleted"
  },
  "nb": {
    "pages.title": "Sider og seksjoner",
    "pages.subtitle": "Innholdsadministrasjon",
    "pages.index": "Oversikt",
    "pages.actions": "Handlinger",
    "pages.new": "Ny side",
    "pages.reprocess": "Behandle sider/seksjoner på nytt",
    "pages.delete-section": "Slett seksjon",
    "pages.edit-page": "Rediger side",
    "pages.new-section": "Ny seksjon",
    "pages.section": "Seksjon",
    "pages.sequence-updated": "Rekkefølge oppdatert",
    "pages.are-you-sure-you-want-to-delete-this-section": "Er du sikker på at du vil slette denne seksjonen?",
    "pages.delete-page": "Slett siden",
    "pages.duplicate-page": "Dupliser side",
    "pages.edit-section": "Rediger seksjon",
    "pages.reprocess-page": "Behandle siden på nytt",
    "pages.section-deleted": "Seksjon slettet"
  }
}
</i18n>
