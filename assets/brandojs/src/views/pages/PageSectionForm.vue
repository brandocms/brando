<template>
  <KForm
    v-if="!loading"
    :back="{ name: 'pages' }"
    @save="save">

    <section class="row">
      <div class="half">
        <KInput
          v-model="page.title"
          rules="required"
          name="page[title]"
          type="text"
          label="Tittel"
          placeholder="Tittel" />
        <KInputSelect
          v-model="page.language"
          rules="required"
          :options="[
            { name: 'English', value: 'en' },
            { name: 'Norsk', value: 'no' }
          ]"
          optionValueKey="value"
          name="page[language]"
          label="Språk"/>
        <section class="row">
          <div class="half">
            <KInput
              v-model="page.parent_key"
              rules="required"
              name="page[parent_key]"
              type="text"
              label="Hovednøkkel"
              placeholder="Hovednøkkel" />
          </div>
          <div class="half">

            <KInput
              v-model="page.key"
              rules="required"
              name="page[key]"
              type="text"
              label="Nøkkel"
              placeholder="Nøkkel" />
          </div>
        </section>
      </div>

      <div class="half">
        <KInputSelect
          v-model="page.page_id"
          rules="required"
          :options="parents"
          name="page[page_id]"
          optionValueKey="value"
          label="Tilhørende side" />
        <KInputTextarea
          v-model="page.wrapper"
          :monospace="true"
          :rows="10"
          name="page[wrapper]"
          type="text"
          label="HTML wrapper (avansert)"
          help-text="Tilgjengelige variabler: ${CONTENT}, ${PARENT_KEY}, ${KEY}, ${LANGUAGE}"></KInputTextarea>
      </div>
    </section>
    <Villain
      v-model="page.data"
      rules="required"
      :template-mode="settings.templateMode"
      :templates="settings.templateNamespace"
      name="page[data]"
      label="Innhold"/>
  </KForm>
</template>

<script>
export default {
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
        templateMode: false,
        templateNamespace: 'all',
        namespacedTemplates: []
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    this.getParents()
  },

  methods: {
    getParents () {
      console.log(this.adminChannel)
      this.adminChannel.channel
        .push('pages:list_parents')
        .receive('ok', payload => {
          this.parents = payload.parents
          this.loading = 0
        })
        .receive('error', err => {
          console.log(err)
          this.loading = 0
        })
    }
  }
}
</script>

<style>

</style>
