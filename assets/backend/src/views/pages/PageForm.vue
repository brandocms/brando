<template>
  <KForm
    v-if="page && GLOBALS.identity"
    :back="{ name: 'pages' }"
    @save="save">
    <section class="row">
      <div class="sized">
        <KInputToggle
          v-model="advancedConfig"
          name="config[advanced]"
          :label="$t('fields.advancedConfig.label')" />
      </div>
    </section>
    <section class="row">
      <div class="sized">
        <KInputStatus
          v-model="page.status"
          name="page[status]"
          rules="required"
          label="Status" />

        <KInputSelect
          v-model="page.language"
          rules="required"
          :options="GLOBALS.identity.languages"
          option-value-key="id"
          name="page[language]"
          :label="$t('fields.language.label')" />

        <KInputSelect
          v-if="parents && parents.entries"
          v-model="page.parentId"
          :options="parents.entries"
          option-value-key="id"
          option-label-key="title"
          name="page[parentId]"
          :label="$t('fields.parentId.label')">
          <template #label="{ option }">
            <template v-if="option.parentId">
              {{ findParent(option.parentId) }} &rarr;
            </template><template v-else>
              [{{ option.language.toUpperCase() }}]
            </template>{{ option.title }}
          </template>
        </KInputSelect>

        <KInput
          v-model="page.title"
          :label="$t('fields.title.label')"
          :placeholder="$t('fields.title.label')"
          rules="required"
          name="page[title]" />

        <KInput
          v-model="page.uri"
          monospace
          rules="required"
          name="page[uri]"
          type="text"
          :label="$t('fields.uri.label')"
          :placeholder="$t('fields.uri.label')" />
      </div>
      <div class="half">
        <fieldset>
          <KInputToggle
            v-model="page.isHomepage"
            name="config[isHomepage]"
            :label="$t('fields.isHomepage.label')" />

          <KInputSelect
            v-if="templates"
            v-model="page.template"
            rules="required"
            :options="templates"
            option-value-key="value"
            name="page[template]"
            :label="$t('fields.template.label')" />

          <KInput
            v-model="page.cssClasses"
            name="page[cssClasses]"
            type="text"
            :placeholder="$t('fields.cssClasses.label')"
            :label="$t('fields.cssClasses.label')" />
        </fieldset>
      </div>
    </section>
    <KInputTable
      v-if="advancedConfig"
      v-model="page.properties"
      :new-entry-template="{ type: 'boolean', label: '', key: '', data: { value: ''}}"
      :delete-rows="true"
      :edit-rows="true"
      :add-rows="true"
      :fixed-layout="false"
      class="bordered"
      :name="`page[properties]`"
      :label="$t('fields.properties.label')">
      <template #head>
        <tr>
          <th>{{ $t('pages.label') }}</th>
          <th>{{ $t('pages.key') }}</th>
          <th>{{ $t('pages.type') }}</th>
          <th>{{ $t('pages.value') }}</th>
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
            :name="`prop[label]`" />
        </td>
        <td class="monospace">
          <KInput
            v-model="editEntry.key"
            :name="`prop[key]`" />
        </td>
        <td class="monospace">
          <KInputSelect
            v-model="editEntry.type"
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
              :name="`prop[data][value]`" />
          </template>
          <template v-else-if="editEntry.type === 'boolean'">
            <KInputToggle
              v-model="editEntry.data.value"
              :name="`prop[data][value]`" />
          </template>
          <template v-if="editEntry.type === 'html'">
            <KInputRichText
              v-model="editEntry.data.value"
              :name="`prop[data][value]`" />
          </template>
          <template v-if="editEntry.type === 'color'">
            <KInputColor
              v-model="editEntry.data.value"
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
      v-for="prop in page.properties"
      v-else>
      <template v-if="prop.type === 'text'">
        <KInput
          :key="prop.key"
          v-model="prop.data.value"
          :label="prop.label"
          :name="`prop[${prop.key}][value]`" />
      </template>
      <template v-else-if="prop.type === 'boolean'">
        <KInputToggle
          :key="prop.key"
          v-model="prop.data.value"
          :label="prop.label"
          :name="`prop[${prop.key}][value]`" />
      </template>
      <template v-if="prop.type === 'html'">
        <KInputRichText
          :key="prop.key"
          v-model="prop.data.value"
          :label="prop.label"
          :name="`prop[${prop.key}][value]`" />
      </template>
      <template v-if="prop.type === 'color'">
        <KInputColor
          :key="prop.key"
          v-model="prop.data.value"
          :label="prop.label"
          :name="`prop[${prop.key}][value]`" />
      </template>
    </template>
    <Villain
      v-model="page.data"
      rules="required"
      :entry-data="page"
      :module-mode="moduleMode()"
      :modules="$app.modules"
      :label="$t('fields.data.label')"
      name="page[data]" />
  </KForm>
</template>

<script>
import gql from 'graphql-tag'
import LivePreview from '../../mixins/LivePreview'
import Revisions from '../../mixins/Revisions'
import Meta from '../../mixins/Meta'
import ScheduledPublishing from '../../mixins/ScheduledPublishing'
import locale from '../../locales/pages'

export default {
  mixins: [
    ScheduledPublishing({
      prop: 'page'
    }),

    Meta({
      prop: 'page'
    }),

    LivePreview({
      schema: 'Brando.Pages.Page',
      prop: 'page',
      key: 'data'
    }),

    Revisions({
      schema: 'Brando.Pages.Page',
      prop: 'page',
      key: 'id'
    })
  ],

  inject: [
    'adminChannel',
    'GLOBALS'
  ],

  props: {
    page: {
      type: Object,
      default: () => {}
    },

    save: {
      type: Function,
      required: true
    }
  },

  data () {
    return {
      advancedConfig: false,
      templates: null,
      settings: {
        namespacedTemplates: []
      }
    }
  },

  created () {
    this.adminChannel.channel
      .push('pages:list_templates', {})
      .receive('ok', payload => {
        this.templates = payload.templates
      })
  },

  mounted () {
    this.advancedConfig = false
  },

  methods: {
    findParent (id) {
      const parent = this.parents.entries.find(p => parseInt(p.id) === parseInt(id))
      if (parent) {
        return `[${parent.language.toUpperCase()}] ${parent.title}`
      }
      return ''
    },

    moduleMode () {
      if (typeof this.$app.moduleMode === 'function') {
        return this.$app.moduleMode(this.page)
      }
      return this.$app.moduleMode
    }
  },

  apollo: {
    parents: {
      query: gql`
        query Parents {
          parents: pages {
            entries {
              id
              language
              title
              uri
              parentId
            }
          }
        }
      `,

      update ({ parents }) {
        if (this.page) {
          if (this.page.parentId) {
            if (!this.page.uri) {
              const parent = parents.entries.find(p => parseInt(p.id) === parseInt(this.page.parentId))
              if (parent) {
                this.$set(this.page, 'uri', parent.uri + '/path')
              }
            }
          }
        }

        return parents
      }
    }
  },
  i18n: {
    sharedMessages: locale
  }
}
</script>

<style>

</style>
