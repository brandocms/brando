<template>
  <div>
    <ContentHeader>
      <template v-slot:title>
        Identitet
      </template>
      <template v-slot:subtitle>
        Konfigurasjon
      </template>
      <template v-slot:help>
        <p>
          Konfigurasjon av virksomhetens identitet og SEO/JSONLD.
        </p>
      </template>
    </ContentHeader>
    <KForm
      v-if="identity"
      :back="{ name: 'dashboard' }"
      back-text="Tilbake til dashbordet"
      @save="save">
      <template v-slot>
        <KInputRadios
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
          <div class="half">
            <KInput
              v-model="identity.name"
              rules="required"
              :value="identity.name"
              name="identity[name]"
              label="Navn"
              placeholder="Navn" />
          </div>

          <div class="half">
            <KInput
              v-model="identity.alternate_name"
              :value="identity.alternate_name"
              name="identity[alternate_name]"
              label="Kortere form av navnet"
              placeholder="AB" />
          </div>
        </div>

        <div class="row">
          <div class="half">
            <KInput
              v-model="identity.email"
              :value="identity.email"
              name="identity[email]"
              label="Epost"
              placeholder="Epost" />
          </div>
          <div class="half">
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
          <div class="third">
            <KInput
              v-model="identity.zipcode"
              :value="identity.zipcode"
              name="identity[zipcode]"
              label="Postnr"
              placeholder="Postnr" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.city"
              :value="identity.city"
              name="identity[city]"
              label="By"
              placeholder="By" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.country"
              :value="identity.country"
              name="identity[country]"
              label="Land"
              placeholder="NO" />
          </div>
        </div>

        <KInput
          v-model="identity.description"
          rules="required"
          :value="identity.description"
          name="identity[description]"
          label="Beskrivelse"
          placeholder="Beskrivelse" />

        <div class="row">
          <div class="third">
            <KInput
              v-model="identity.title_prefix"
              :value="identity.title_prefix"
              name="identity[title_prefix]"
              label="Tittel prefiks"
              placeholder="AB | " />
          </div>
          <div class="third">
            <KInput
              v-model="identity.title"
              :value="identity.title"
              name="identity[title]"
              label="Hovedtittel (fallback)"
              placeholder="Tittel" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.title_postfix"
              :value="identity.title_postfix"
              name="identity[title_postfix]"
              label="Tittel postfiks"
              placeholder=" | AB" />
          </div>
        </div>

        <div class="row">
          <div class="half">
            <KInputImage
              v-model="identity.image"
              :value="identity.image"
              name="identity[image]"
              label="Bilde" />
          </div>
          <div class="half">
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

        <KInputTable
          v-model="identity.links"
          name="user[links]"
          label="Linker (sosiale medier)">
          <template v-slot:head>
            <tr>
              <th>Navn</th>
              <th>URL</th>
              <th></th>
            </tr>
          </template>
          <template v-slot:row="{ entry }">
            <td>
              {{ entry.name }}
            </td>
            <td>
              {{ entry.url }}
            </td>
          </template>
          <template v-slot:new="{ newEntry }">
            <td>
              <input
                v-model="newEntry.name"
                type="text">
            </td>
            <td>
              <input
                v-model="newEntry.url"
                type="text">
            </td>
          </template>
        </KInputTable>

        <KInputTable
          v-model="identity.metas"
          name="user[metas]"
          label="META variabler">
          <template v-slot:head>
            <tr>
              <th>Nøkkel</th>
              <th>Verdi</th>
              <th></th>
            </tr>
          </template>
          <template v-slot:row="{ entry }">
            <td>
              {{ entry.key }}
            </td>
            <td>
              {{ entry.value }}
            </td>
          </template>
          <template v-slot:new="{ newEntry }">
            <td>
              <input
                v-model="newEntry.key"
                type="text">
            </td>
            <td>
              <input
                v-model="newEntry.value"
                type="text">
            </td>
          </template>
        </KInputTable>

      </template>
    </KForm>
  </div>
</template>

<script>
import gql from 'graphql-tag'
// import nprogress from 'nprogress'
// import { showError, validateImageParams, stripParams } from '../../utils'
// import { alertError } from '../../utils/alerts'
// import { identityAPI } from '../../api/identity'

export default {
  data () {
    return {
      loading: 0,
      identity: {},
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

  // inject: [
  //   'adminChannel'
  // ],

  async created () {
    this.loading++
    // const v = await identityAPI.getIdentity()
    // this.identity = { ...v }
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

    async save () {
      const params = this.$utils.stripParams(this.identity, ['__typename', 'id'])
      this.$utils.validateImageParams(params, ['logo', 'image'])
      params.links.map(item => (delete item.__typename))
      params.metas.map(item => (delete item.__typename))

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateIdentity($identityParams: IdentityParams) {
              updateIdentity(
                identityParams: $identityParams,
              ) {
                id
                type
                name
                alternate_name
                email
                phone
                address
                zipcode
                city
                country
                description
                title_prefix
                title
                title_postfix

                image {
                  thumb: url(size: "original")
                  focal
                }

                logo {
                  thumb: url(size: "original")
                  focal
                }

                links {
                  id
                  name
                  url
                }

                metas {
                  id
                  key
                  value
                }

                configs {
                  id
                  key
                  value
                }

                url
              }
            }
          `,
          variables: {
            identityParams: params
          }
        })

        this.$toast.success({ message: 'Identitet oppdatert' })
        this.$router.push({ name: 'dashboard' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    identity: {
      query: gql`
        query Identity {
          identity {
            id
            type
            name
            alternate_name
            email
            phone
            address
            zipcode
            city
            country
            description
            title_prefix
            title
            title_postfix

            image {
              thumb: url(size: "original")
              focal
            }

            logo {
              thumb: url(size: "original")
              focal
            }

            links {
              id
              name
              url
            }

            metas {
              id
              key
              value
            }

            configs {
              id
              key
              value
            }

            url
          }
        }
      `
    }
  }
}
</script>
