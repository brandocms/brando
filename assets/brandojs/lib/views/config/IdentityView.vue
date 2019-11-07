<template>
  <div
    v-if="!loading"
    class="create-identity">
    <div class="container">
      <div class="card">
        <div class="card-header">
          <h5 class="section mb-0">
            Endre
          </h5>
        </div>
        <div class="card-body">
          <ValidationObserver
            ref="observer">
            <KInputSelect
              v-model="identity.type"
              rules="required"
              :value="identity.type"
              :options="[
                { name: 'Organisasjon', value: 'organization' },
                { name: 'Bedrift', value: 'corporation' }
              ]"
              name="identity[type]"
              label="Type"
              data-vv-name="identity[type]"
              data-vv-value-path="innerValue" />

            <div class="row">
              <div class="col">
                <KInput
                  v-model="identity.name"
                  rules="required"
                  :value="identity.name"
                  name="identity[name]"
                  label="Navn"
                  placeholder="Navn" />
              </div>

              <div class="col">
                <KInput
                  v-model="identity.alternate_name"
                  :value="identity.alternate_name"
                  name="identity[alternate_name]"
                  label="Kortere form av navnet"
                  placeholder="AB" />
              </div>
            </div>

            <div class="row">
              <div class="col">
                <KInput
                  v-model="identity.email"
                  :value="identity.email"
                  name="identity[email]"
                  label="Epost"
                  placeholder="Epost" />
              </div>
              <div class="col">
                <KInput
                  v-model="identity.phone"
                  :value="identity.phone"
                  name="identity[phone]"
                  label="Telefon"
                  placeholder="Telefon" />
              </div>
            </div>

            <KInput
              v-model="identity.address"
              :value="identity.address"
              name="identity[address]"
              label="Adresse"
              placeholder="Adresse" />

            <div class="row">
              <div class="col">
                <KInput
                  v-model="identity.zipcode"
                  :value="identity.zipcode"
                  name="identity[zipcode]"
                  label="Postnr"
                  placeholder="Postnr" />
              </div>
              <div class="col">
                <KInput
                  v-model="identity.city"
                  :value="identity.city"
                  name="identity[city]"
                  label="By"
                  placeholder="By" />
              </div>
            </div>

            <KInput
              v-model="identity.country"
              :value="identity.country"
              name="identity[country]"
              label="Land"
              placeholder="NO" />

            <KInput
              v-model="identity.description"
              rules="required"
              :value="identity.description"
              name="identity[description]"
              label="Beskrivelse"
              placeholder="Beskrivelse" />

            <div class="row">
              <div class="col">
                <KInput
                  v-model="identity.title_prefix"
                  :value="identity.title_prefix"
                  name="identity[title_prefix]"
                  label="Tittel prefiks"
                  placeholder="AB | " />
              </div>
              <div class="col">
                <KInput
                  v-model="identity.title"
                  :value="identity.title"
                  name="identity[title]"
                  label="Hovedtittel (fallback)"
                  placeholder="Tittel" />
              </div>
              <div class="col">
                <KInput
                  v-model="identity.title_postfix"
                  :value="identity.title_postfix"
                  name="identity[title_postfix]"
                  label="Tittel postfiks"
                  placeholder=" | AB" />
              </div>
            </div>

            <div class="row">
              <div class="col">
                <KInputImage
                  v-model="identity.image"
                  :value="identity.image"
                  name="identity[image]"
                  label="Bilde" />
              </div>
              <div class="col">
                <KInputImage
                  v-model="identity.logo"
                  :value="identity.logo"
                  name="identity[logo]"
                  label="Logo" />
              </div>
            </div>

            <KInput
              v-model="identity.url"
              rules="required"
              :value="identity.url"
              name="identity[url]"
              label="URL"
              placeholder="URL" />

            <div class="form-group">
              <div class="label-wrapper">
                <label
                  class="control-label">
                  META variabler
                </label>
              </div>
              <table class="table">
                <tr
                  v-for="meta in identity.metas"
                  :key="meta.id">
                  <td>
                    {{ meta.key }}
                  </td>
                  <td>
                    {{ meta.value }}
                  </td>
                  <td class="fit">
                    <button
                      class="btn btn-danger"
                      @click="deletemeta(meta)">
                      Slett
                    </button>
                  </td>
                </tr>
                <tr>
                  <td>
                    <input
                      v-model="newmeta.key"
                      class="form-control"
                      type="text"
                      placeholder="Nøkkel">
                  </td>
                  <td>
                    <input
                      v-model="newmeta.value"
                      class="form-control"
                      type="url"
                      placeholder="Verdi">
                  </td>
                  <td class="fit">
                    <button
                      class="btn btn-success"
                      @click="addmeta">
                      Legg til
                    </button>
                  </td>
                </tr>
              </table>
            </div>

            <div class="form-group">
              <div class="label-wrapper">
                <label
                  class="control-label">
                  Linker (sosiale medier)
                </label>
              </div>
              <table class="table">
                <tr
                  v-for="link in identity.links"
                  :key="link.id">
                  <td>
                    {{ link.name }}
                  </td>
                  <td>
                    {{ link.url }}
                  </td>
                  <td class="fit">
                    <button
                      class="btn btn-danger"
                      @click="deletelink(link)">
                      Slett
                    </button>
                  </td>
                </tr>
                <tr>
                  <td>
                    <input
                      v-model="newlink.name"
                      class="form-control"
                      type="text"
                      placeholder="Navn">
                  </td>
                  <td>
                    <input
                      v-model="newlink.url"
                      class="form-control"
                      type="url"
                      placeholder="URL">
                  </td>
                  <td class="fit">
                    <button
                      class="btn btn-success"
                      @click="addlink">
                      Legg til
                    </button>
                  </td>
                </tr>
              </table>
            </div>

            <button
              :disabled="!!loading"
              class="btn btn-secondary"
              @click="validate">
              Lagre
            </button>
          </ValidationObserver>
        </div>
      </div>
    </div>
  </div>
</template>

<script>

import nprogress from 'nprogress'
import { showError, validateImageParams, stripParams } from '../../utils'
import { alertError } from '../../utils/alerts'
import { identityAPI } from '../../api/identity'

export default {
  data () {
    return {
      loading: 0,
      identity: null,
      newlink: {
        name: '',
        url: ''
      },
      newmeta: {
        key: '',
        value: ''
      }
    }
  },

  inject: [
    'adminChannel'
  ],

  async created () {
    this.loading++
    const v = await identityAPI.getIdentity()
    this.identity = { ...v }
    this.loading--
  },

  methods: {
    addlink () {
      this.identity.links.push({
        name: this.newlink.name,
        url: this.newlink.url
      })
      this.newlink.name = ''
      this.newlink.url = ''
    },

    deletelink (link) {
      const l = this.identity.links.find(l => l.id === link.id)
      const idx = this.identity.links.indexOf(l)
      this.identity.links = [
        ...this.identity.links.slice(0, idx),
        ...this.identity.links.slice(idx + 1)
      ]
    },

    addmeta () {
      this.identity.metas.push({
        key: this.newmeta.key,
        value: this.newmeta.value
      })
      this.newmeta.key = ''
      this.newmeta.value = ''
    },

    deletemeta (meta) {
      const l = this.identity.metas.find(l => l.id === meta.id)
      const idx = this.identity.metas.indexOf(l)
      this.identity.metas = [
        ...this.identity.metas.slice(0, idx),
        ...this.identity.metas.slice(idx + 1)
      ]
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
      this.loading = false
      let params = { ...this.identity }

      // strip out params we don't want sent in the mutation
      stripParams(params, ['__typename', 'id'])

      params.links.map((item) => (
        delete item.__typename
      ))

      params.metas.map((item) => (
        delete item.__typename
      ))

      // validate image params, if any, to ensure they are files
      validateImageParams(params, ['image', 'logo'])

      try {
        nprogress.start()
        await identityAPI.updateIdentity(params)
        nprogress.done()
        this.$toast.success({ message: 'Objekt endret' })
      } catch (err) {
        showError(err)
      }
    }
  }
}
</script>
