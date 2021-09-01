<template>
  <KForm
    v-if="!loading && GLOBALS.identity"
    :back="{ name: 'pages' }"
    @save="save">
    <section class="row">
      <div class="half">
        <KInput
          v-model="page.title"
          rules="required"
          name="page[title]"
          type="text"
          :label="$t('title')"
          :placeholder="$t('title')" />
        <KInputSelect
          v-model="page.language"
          rules="required"
          :options="GLOBALS.identity.languages"
          option-value-key="id"
          name="page[language]"
          :label="$t('language')" />
        <section class="row">
          <div class="half">
            <KInput
              v-model="page.parentKey"
              rules="required"
              name="page[parentKey]"
              type="text"
              :label="$t('parentKey')"
              :placeholder="$t('parentKey')" />
          </div>
          <div class="half">
            <KInput
              v-model="page.key"
              rules="required"
              name="page[key]"
              type="text"
              :label="$t('key')"
              :placeholder="$t('key')" />
          </div>
        </section>
      </div>

      <div class="half">
        <KInputSelect
          v-model="page.pageId"
          rules="required"
          :options="parents"
          name="page[pageId]"
          option-value-key="value"
          :label="$t('pageId')" />
        <KInputTextarea
          v-model="page.wrapper"
          :monospace="true"
          :rows="10"
          name="page[wrapper]"
          type="text"
          :label="$t('wrapper')"
          :help-text="$t('wrapperHelp')"></KInputTextarea>
      </div>
    </section>
    <Villain
      v-model="page.data"
      rules="required"
      :entry-data="page"
      :module-mode="moduleMode()"
      :modules="$app.modules"
      name="page[data]"
      :label="$t('content')" />
  </KForm>
</template>

<script>

import gql from 'graphql-tag'

export default {
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
      loading: 1,
      parents: [],
      settings: {
        namespacedTemplates: []
      }
    }
  },

  created () {
    this.getParents()
  },

  methods: {
    moduleMode () {
      if (typeof this.$app.moduleMode === 'function') {
        return this.$app.moduleMode(this.page)
      }
      return this.$app.moduleMode
    },

    getParents () {
      this.adminChannel.channel
        .push('pages:list_parents', {})
        .receive('ok', payload => {
          this.parents = payload.parents
          this.loading = 0
        })
        .receive('error', err => {
          console.error(err)
          this.loading = 0
        })
    }
  }
}
</script>

<i18n>
  {
    "en": {
      "title": "Title",
      "language": "Language",
      "parentKey": "Parent key",
      "key": "Key",
      "pageId": "Parent page",
      "wrapper": "HTML wrapper (advanced)",
      "wrapperHelp": "Available variables: {{ content }}, {{ parent_key }}, {{ key }}, {{ language }}",
      "data": "Content"
    },
    "no": {
      "title": "Tittel",
      "language": "Språk",
      "parentKey": "Hovednøkkel",
      "key": "Nøkkel",
      "pageId": "Tilhørende side",
      "wrapper": "HTML wrapper (avansert)",
      "wrapperHelp": "Tilgjengelige variabler: {{ content }}, {{ parent_key }}, {{ key }}, {{ language }}",
      "data": "Innhold"
    }
  }
</i18n>
