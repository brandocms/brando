<template>
  <article>
    <ContentHeader>
      <template #title>
        {{ $t('modules.title') }}
      </template>
      <template #subtitle>
        {{ $t('modules.subtitle') }}
      </template>
      <template #help>
        <div>
          <Dropdown>
            <template #default>
              {{ $t('modules.actions') }}
            </template>
            <template #content>
              <li>
                <button
                  type="button"
                  @click="createBlankModule">
                  {{ $t('modules.new') }}
                </button>
              </li>
              <li>
                <button
                  @click="showImportModules = true">
                  {{ $t('modules.import-modules') }}
                </button>
              </li>
            </template>
          </Dropdown>
        </div>
      </template>
    </ContentHeader>

    <KModal
      v-if="showImportModules"
      ref="importModal"
      v-shortkey="['esc', 'enter']"
      ok-text="OK"
      @shortkey.native="showImportModules = false"
      @ok="importModules">
      <template #header>
        {{ $t('modules.import-modules') }}
      </template>
      <KInputTextarea
        v-model="importModulesJSON"
        label="JSON"
        name="modules[import]" />
    </KModal>

    <div class="row">
      <div class="half">
        <h2>{{ $t('modules.index') }}</h2>
      </div>
    </div>
    <ContentList
      v-if="modules"
      :entries="modules"
      :sortable="true"
      :filter-keys="['name', 'namespace']"
      @updateQuery="queryVars = $event"
      @sort="sortEntries">
      <template #selected="{ entries, clearSelection}">
        <li>
          <button
            @click="exportModules(entries, clearSelection)">
            {{ $t('modules.export-modules') }}
          </button>
          <button
            @click="deleteEntries(entries, clearSelection)">
            {{ $t('modules.delete-modules') }}
          </button>
        </li>
      </template>
      <template #row="{ entry }">
        <div class="col-2 mono">
          <div class="badge">
            {{ entry.namespace }}
          </div>
        </div>
        <div class="col-2">
          <div
            class="svg-wrapper"
            v-html="entry.svg" />
        </div>
        <div class="col-10 title mono">
          <router-link
            :to="{ name: 'modules-edit', params: { moduleId: entry.id } }"
            class="link name-link">
            {{ entry.name }}
          </router-link><br>
        </div>
        <div class="col-1">
          <CircleDropdown>
            <li>
              <router-link
                :to="{ name: 'modules-edit', params: { moduleId: entry.id } }">
                {{ $t('modules.edit-module') }}
              </router-link>
            </li>

            <li>
              <button
                type="button"
                @click="duplicateEntry(entry)">
                {{ $t('modules.duplicate-module') }}
              </button>
            </li>

            <li>
              <button
                type="button"
                @click="deleteEntry(entry.id)">
                {{ $t('modules.delete-module') }}
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
import GET_MODULES from '../../gql/pages/MODULES_QUERY.graphql'
import locale from '../../locales/modules'

export default {

  inject: ['adminChannel'],
  data () {
    return {
      showImportModules: false,
      importModulesJSON: '',
      visibleChildren: [],
      queryVars: {
        filter: null,
        offset: 0,
        limit: 50
      }
    }
  },

  methods: {
    exportModules (entries, clearSelection) {
      const exportJSON = entries.map(st => {
        return this.modules.find(t => t.id === st)
      })

      navigator.clipboard.writeText(JSON.stringify(exportJSON))
      this.$toast.success({ message: 'Copied to clipboard' })
      clearSelection()
    },

    async importModules () {
      if (this.importModulesJSON === '') {
        await this.$refs.importModal.close()
        this.showImportModules = false
        return
      }

      const importedModules = JSON.parse(this.importModulesJSON)

      importedModules.forEach(t => {
        if (!t.class) {
          this.$toast.error({ message: 'Error in module format. No data.class found' })
          return
        }

        delete t.id
        delete t.insertedAt
        delete t.updatedAt
        delete t.deletedAt
        delete t.__typename

        t.refs = JSON.stringify(t.refs)
        t.vars = JSON.stringify(t.vars)

        this.$alerts.alertConfirm('OBS', `Are you sure you want to import this module?<br><br>${t.namespace}: <strong>${t.class}</strong>`, async (data) => {
          if (!data) {
            return
          }
          this.createModule(t, false)
        })
      })

      await this.$refs.importModal.close()
      this.showImportModules = false
    },

    createBlankModule () {
      const params = {
        name: 'New module',
        namespace: 'general',
        class: 'module',
        code: '<article b-tpl="module">\n\t<div class="inner">\n\t\t/* */\n\t</div>\n</article>',
        helpText: 'Help text',
        refs: '[]',
        vars: '{}'
      }

      this.createModule(params)
    },

    async createModule (params, gotoModule = true) {
      const moduleParams = params

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateModule($moduleParams: ModuleParams!) {
              createModule(moduleParams: $moduleParams) {
                id
              }
            }
          `,
          variables: {
            moduleParams
          },

          update: (store, { data: { createModule } }) => {
            this.$apollo.queries.modules.refresh()
            if (gotoModule) {
              this.$router.push({ name: 'modules-edit', params: { moduleId: createModule.id } })
            }
          }
        })

        this.$toast.success({ message: this.$t('modules.module-create') })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    sortEntries (seq) {
      this.adminChannel.channel
        .push('villain:sequence_modules', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('modules.sequence-updated') })
        })
    },

    async duplicateEntry (module) {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation DuplicateModule($moduleId: ID!) {
              duplicateModule(moduleId: $moduleId) {
                id
              }
            }
          `,
          variables: {
            moduleId: module.id
          },

          update: (store, { data: { duplicateModule } }) => {
            this.$apollo.queries.modules.refresh()
          }
        })

        this.$toast.success({ message: this.$t('modules.module-duplicated') })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    async deleteEntry (entryId, override) {
      const fn = async () => {
        try {
          await this.$apollo.mutate({
            mutation: gql`
              mutation DeleteModule($moduleId: ID!) {
                deleteModule(moduleId: $moduleId) {
                  id
                }
              }
            `,
            variables: {
              moduleId: entryId
            },

            update: (store, { data: { deleteModule } }) => {
              this.$apollo.queries.modules.refresh()
            }
          })

          this.$toast.success({ message: this.$t('modules.module-deleted') })
        } catch (err) {
          this.$utils.showError(err)
        }
      }

      if (override) {
        fn()
      } else {
        this.$alerts.alertConfirm('OBS', this.$t('modules.delete-confirm'), async confirm => {
          if (!confirm) {
            return false
          } else {
            fn()
          }
        })
      }
    },

    deleteEntries (entries, clearSelection) {
      this.$alerts.alertConfirm('OBS', this.$t('modules.delete-confirm-many'), async data => {
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
    modules: {
      query: GET_MODULES,
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

  >>> .svg-wrapper {
    svg {
      width: 100%;
      height: auto;
    }
  }
</style>
