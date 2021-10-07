<template>
  <div>
    <ContentHeader>
      <template #title>
        {{ $t('title') }}
      </template>
      <template #subtitle>
        {{ $t('subtitle') }}
      </template>
      <template #help>
        <p>
          {{ $t('help') }}
        </p>
      </template>
    </ContentHeader>

    <KInputToggle
      v-if="$can('admin', 'Globals')"
      v-model="editing"
      name="data[editing]"
      :label="$t('editing')" />

    <ButtonPrimary
      v-if="editing"
      class="add-category-btn"
      @click="showNewCategoryModal = true">
      {{ $t('category-add') }}
    </ButtonPrimary>

    <KModal
      v-if="showNewCategoryModal"
      ref="modal"
      v-shortkey="['esc']"
      ok-text="Lagre"
      @shortkey.native="closeModal"
      @ok="saveNewCategory"
      @cancel="closeModal">
      <template #header>
        {{ $t('category-add') }}
      </template>
      <KInput
        v-model="newCategory.label"
        :name="`category[label]`"
        rules="required"
        :label="$t('label')" />

      <KInputSlug
        v-model="newCategory.key"
        :from="newCategory.label"
        :name="`category[key]`"
        rules="required"
        :label="$t('key')" />
    </KModal>

    <template v-if="globalCategories">
      <KForm
        v-for="category in globalCategories"
        :key="category.id"
        :back-text="$t('back-to-dashboard')"
        @save="saveCategory(category)">
        <template #default>
          <div class="category">
            <h3>
              {{ category.label }}
            </h3>
            <template v-if="editing">
              <KInput
                v-model="category.label"
                monospace
                :name="`category[${category.id}][label]`"
                rules="required"
                :label="$t('category') + '-' + $t('label')" />

              <KInput
                v-model="category.key"
                monospace
                :name="`category[${category.id}][key]`"
                rules="required"
                :label="$t('category') + '-' + $t('key')" />
            </template>

            <KInputTable
              v-if="editing"
              v-model="category.globals"
              :new-entry-template="{ type: 'boolean', label: '', key: '', data: { value: ''}}"
              :delete-rows="true"
              :edit-rows="true"
              :add-rows="true"
              :fixed-layout="false"
              class="bordered"
              :name="`category[${category.id}][globals]`"
              :label="$t('variables')">
              <template #head>
                <tr>
                  <th>{{ $t('label') }}</th>
                  <th>{{ $t('key') }}</th>
                  <th>{{ $t('type') }}</th>
                  <th>{{ $t('value') }}</th>
                  <th></th>
                </tr>
              </template>
              <template #row="{ entry }">
                <td class="monospace">
                  {{ entry.label }}
                </td>
                <td class="monospace">
                  {{ entry.key }}
                </td>
                <td class="monospace">
                  {{ entry.type }}
                </td>
                <td class="monospace">
                  <template v-if="entry.type === 'text'">
                    {{ entry.data.value }}
                  </template>
                  <template v-else-if="entry.type === 'boolean'">
                    <CheckOrX :val="entry.data.value" />
                  </template>
                  <template v-else-if="entry.type === 'html'">
                    {{ entry.data.value }}
                  </template>
                  <template v-else-if="entry.type === 'datetime'">
                    {{ entry.data.value }}
                  </template>
                  <template v-else-if="entry.type === 'color'">
                    <svg
                      style="display: inline-block; margin-right: 5px;"
                      width="15"
                      height="15">
                      <circle
                        :fill="entry.data.value"
                        cx="7.5"
                        cy="7.5"
                        r="7.5" />
                    </svg>{{ entry.data.value }}
                  </template>
                </td>
              </template>
              <template #edit="{ editEntry }">
                <td class="monospace">
                  <KInput
                    v-model="editEntry.label"
                    compact
                    :name="`prop[label]`" />
                </td>
                <td class="monospace">
                  <KInput
                    v-model="editEntry.key"
                    compact
                    :name="`prop[key]`" />
                </td>
                <td class="monospace">
                  <KInputSelect
                    v-model="editEntry.type"
                    compact
                    :name="`prop[type]`"
                    :options="[
                      {
                        id: 'boolean',
                        name: 'Boolean',
                      }, {
                        id: 'html',
                        name: 'HTML',
                      }, {
                        id: 'text',
                        name: 'text',
                      }, {
                        id: 'datetime',
                        name: 'Datetime',
                      },
                      {
                        id: 'color',
                        name: 'color',
                      }]" />
                </td>
                <td class="monospace">
                  <template v-if="editEntry.type === 'text'">
                    <KInput
                      v-model="editEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-else-if="editEntry.type === 'boolean'">
                    <KInputToggle
                      v-model="editEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="editEntry.type === 'html'">
                    <KInputRichText
                      v-model="editEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="editEntry.type === 'datetime'">
                    <KInputDatetime
                      v-model="editEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="editEntry.type === 'color'">
                    <KInputColor
                      v-model="editEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                </td>
              </template>

              <template
                #new="{ newEntry }">
                <td class="monospace">
                  <KInput
                    v-model="newEntry.label"
                    :name="`prop[label]`"
                    compact />
                </td>
                <td class="monospace">
                  <KInput
                    v-model="newEntry.key"
                    :name="`prop[key]`"
                    compact />
                </td>
                <td class="monospace">
                  <KInputSelect
                    v-model="newEntry.type"
                    compact
                    :name="`prop[type]`"
                    :options="[
                      {
                        id: 'boolean',
                        name: 'Boolean',
                      }, {
                        id: 'html',
                        name: 'HTML',
                      }, {
                        id: 'text',
                        name: 'text',
                      }, {
                        id: 'datetime',
                        name: 'Datetime',
                      },
                      {
                        id: 'color',
                        name: 'color',
                      }]" />
                </td>
                <td class="monospace">
                  <template v-if="newEntry.type === 'text'">
                    <KInput
                      v-model="newEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-else-if="newEntry.type === 'boolean'">
                    <KInputToggle
                      v-model="newEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="newEntry.type === 'html'">
                    <KInputRichText
                      v-model="newEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="newEntry.type === 'datetime'">
                    <KInputDatetime
                      v-model="newEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                  <template v-if="newEntry.type === 'color'">
                    <KInputColor
                      v-model="newEntry.data.value"
                      compact
                      :name="`prop[data][value]`" />
                  </template>
                </td>
              </template>
            </KInputTable>
            <template
              v-for="global in category.globals"
              v-else>
              <template v-if="global.type === 'text'">
                <KInput
                  :key="global.key"
                  v-model="global.data.value"
                  :label="global.label"
                  :name="`prop[${global.key}][value]`" />
              </template>
              <template v-else-if="global.type === 'boolean'">
                <KInputToggle
                  :key="global.key"
                  v-model="global.data.value"
                  :label="global.label"
                  :name="`prop[${global.key}][value]`" />
              </template>
              <template v-if="global.type === 'html'">
                <KInputRichText
                  :key="global.key"
                  v-model="global.data.value"
                  :label="global.label"
                  :name="`prop[${global.key}][value]`" />
              </template>
              <template v-if="global.type === 'datetime'">
                <KInputDatetime
                  :key="global.key"
                  v-model="global.data.value"
                  :label="global.label"
                  :name="`prop[${global.key}][value]`" />
              </template>
              <template v-if="global.type === 'color'">
                <KInputColor
                  :key="global.key"
                  v-model="global.data.value"
                  :label="global.label"
                  :name="`prop[${global.key}][value]`" />
              </template>
            </template>
          </div>
        </template>
      </KForm>
    </template>
  </div>
</template>

<script>
import gql from 'graphql-tag'
import GET_GLOBAL_CATEGORIES from '../../gql/identity/GLOBAL_CATEGORIES_QUERY.graphql'

export default {
  data () {
    return {
      editing: false,
      loading: 0,

      newCategory: { label: '', key: '' },
      showNewCategoryModal: false
    }
  },

  async created () {
    this.loading++
    this.loading--
  },

  methods: {
    async closeModal () {
      await this.$refs.modal.close()
      this.showNewCategoryModal = false
    },

    async closeGlobalModal (callback, entry) {
      await this.$refs.globalModal[0].close()
      if (callback) {
        callback()
      }
    },

    async saveNewCategory () {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateGlobalCategory($globalCategoryParams: GlobalCategoryParams) {
              createGlobalCategory(
                globalCategoryParams: $globalCategoryParams,
              ) {
                id
              }
            }
          `,

          variables: {
            globalCategoryParams: this.newCategory
          },

          update: (store, data) => {
            this.$apollo.queries.globalCategories.refresh()
            this.$toast.success({ message: this.$t('category-created') })
          }
        })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    async saveCategory (category) {
      const strippedCategory = this.$utils.stripParams(category, ['__typename'])
      const globals = strippedCategory.globals.map(g => {
        delete g.__typename
        return { ...g, data: JSON.stringify(g.data) }
      })
      const globalCategoryParams = { ...strippedCategory, globals }

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateGlobalCategory($categoryId: ID!, $globalCategoryParams: GlobalCategoryParams) {
              updateGlobalCategory(
                categoryId: $categoryId,
                globalCategoryParams: $globalCategoryParams,
              ) {
                id
              }
            }
          `,

          variables: {
            categoryId: category.id,
            globalCategoryParams
          },

          update: (store, data) => {
            this.$apollo.queries.globalCategories.refresh()
            this.$toast.success({ message: this.$t('category-saved') })
          }
        })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    globalCategories: {
      query: GET_GLOBAL_CATEGORIES
    }
  }
}
</script>
<style lang="postcss" scoped>
  .empty-globals {
    @color bg peach;
    padding: 1rem 2rem;
    margin-bottom: 25px;
  }

  .add-category-btn {
    @space margin-bottom sm;
  }

  .category {
    h3 {
      @fontsize lg;
      @space margin-bottom sm;
      font-weight: 500;
    }

    >>> .input-table {
      margin-bottom: 0;
    }
  }

  .form-wrapper + .form-wrapper {
    margin-top: 2.5rem;
  }

  .form-wrapper {
    border: 1px solid theme(colors.blue);
    padding: 2rem;
  }
</style>
<i18n>
  {
    "en": {
      "title": "Configuration",
      "subtitle": "Global variables",
      "help": "Configure global variables that can be used all across the website",
      "editing": "Configure global variables (advanced)",
      "category": "Category",
      "category-created": "Category created",
      "category-saved": "Category saved",
      "category-add": "Add category",
      "variables": "Variables",
      "label": "Label",
      "key": "Key",
      "type": "Type",
      "value": "Value",
      "back-to-dashboard": "Back to dashboard"
    },
    "no": {
      "title": "Konfigurasjon",
      "subtitle": "Globale variabler",
      "help": "Konfigurasjon av variabler som kan brukes i innholdsmoduler og generelt på nettsiden",
      "editing": "Administrér globale variabler (avansert)",
      "category": "Kategori",
      "category-created": "Kategori opprettet",
      "category-saved": "Kategori lagret",
      "category-add": "Legg til kategori",
      "variables": "Variabler",
      "label": "Etikett",
      "key": "Nøkkel",
      "type": "Type",
      "value": "Verdi",
      "back-to-dashboard": "Tilbake til dashbordet"
    }
  }
</i18n>
