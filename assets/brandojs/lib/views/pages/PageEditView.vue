<template>
  <ValidationObserver
    ref="observer">
    <div
      v-if="!loading"
      class="create-post">
      <div class="container">
        <div class="row">
          <div class="col-md-9">
            <div class="card h-100">
              <div class="card-header">
                <h5 class="section mb-0">
                  Oppdatér side — Innhold
                </h5>
              </div>
              <div class="card-body">
                <Villain
                  :value="page.data"
                  :templates="settings.templates"
                  :template-mode="settings.templateMode"
                  label="Innhold"
                  name="page[data]"
                  @input="page.data = $event" />
              </div>
            </div>
          </div>
          <div class="col-md-3">
            <div class="card">
              <div class="card-header">
                <h5 class="section mb-0">
                  Oppdatér side — attributter
                </h5>
              </div>
              <div class="card-body">
                <KInputSelect
                  v-model="page.parent_id"
                  :value="page.parent_id"
                  :options="parents"
                  name="page[parent_id]"
                  label="Tilhørende side"
                  data-vv-name="page[parent_id]"
                  data-vv-value-path="innerValue" />

                <KInputSelect
                  v-model="page.language"
                  rules="required"
                  :value="page.language"
                  :options="[
                    { name: 'English', value: 'en' },
                    { name: 'Norsk', value: 'no' }
                  ]"
                  name="page[language]"
                  label="Språk"
                  data-vv-name="page[language]"
                  data-vv-value-path="innerValue" />

                <KInput
                  v-model="page.key"
                  rules="required"
                  :value="page.key"
                  name="page[key]"
                  type="text"
                  label="Nøkkel"
                  placeholder="Nøkkel"
                  data-vv-name="page[key]"
                  data-vv-value-path="innerValue" />

                <KInput
                  v-model="page.title"
                  rules="required"
                  :value="page.title"
                  name="page[title]"
                  type="text"
                  label="Tittel"
                  placeholder="Tittel"
                  data-vv-name="page[title]"
                  data-vv-value-path="innerValue" />

                <div class="row">
                  <div class="col">
                    <KInputTextarea
                      v-model="page.meta_description"
                      :rows="3"
                      name="page[meta_description]"
                      type="text"
                      label="META beskrivelse (for søkemotorer)"
                      data-vv-name="page[meta_description]"
                      data-vv-value-path="innerValue" />
                  </div>
                </div>

                <KInput
                  v-model="page.css_classes"
                  :value="page.css_classes"
                  name="page[css_classes]"
                  type="text"
                  label="Ekstra CSS klasser"
                  placeholder="Ekstra CSS klasser"
                  data-vv-name="page[css_classes]"
                  data-vv-value-path="innerValue" />

                <div class="mt-4">
                  <button
                    :disabled="!!loading"
                    class="btn btn-secondary btn-block"
                    @click="validate">
                    Lagre oppdatert side
                  </button>
                </div>

                <router-link
                  :disabled="!!loading"
                  :to="{ name: 'pages' }"
                  class="btn btn-outline-secondary btn-block mt-2">
                  Tilbake til oversikten
                </router-link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </ValidationObserver>
</template>

<script>

import nprogress from 'nprogress'
import showError from 'brandojs/lib/utils/showError'
import { pageAPI } from 'brandojs/lib/api/page'
import { alertError } from 'brandojs/lib/utils/alerts'
import { mapGetters } from 'vuex'

export default {
  props: {
    pageId: {
      type: [String, Number],
      required: true
    }
  },
  data () {
    return {
      loading: true,
      page: null,
      parents: []
    }
  },

  computed: {
    ...mapGetters('config', [
      'settings'
    ])
  },

  inject: [
    'adminChannel'
  ],

  async created () {
    this.getParents()
    const p = await pageAPI.getPage(this.pageId)
    this.page = { ...p }
    this.loading = false
  },

  methods: {
    getParents () {
      this.adminChannel.channel
        .push('pages:list_parents')
        .receive('ok', payload => {
          this.parents = payload.parents
        })
        .receive('error', err => {
          console.log(err)
        })
    },

    async validate () {
      const isValid = await this.$refs.observer.validate()
      if (!isValid) {
        alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
        this.loading = false
        return
      }
      this.save()
    },

    async save () {
      try {
        nprogress.start()
        await pageAPI.updatePage(this.pageId, this.page)
        nprogress.done()
        this.$toast.success({ message: 'Side oppdatert' })
        this.$router.push({ name: 'pages' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
