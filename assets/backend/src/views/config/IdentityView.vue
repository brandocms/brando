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
        <p>{{ $t('help') }}</p>
      </template>
    </ContentHeader>
    <KForm
      v-if="identity"
      :back="{ name: 'dashboard' }"
      :back-text="$t('back-to-dashboard')"
      @save="save">
      <template #default>
        <KInputRadios
          v-model="identity.type"
          rules="required"
          :options="[
            { name: $t('organization'), value: 'organization' },
            { name: $t('corporation'), value: 'corporation' }
          ]"
          name="identity[type]"
          :label="$t('fields.type.label')" />

        <div class="row">
          <div class="half">
            <KInput
              v-model="identity.name"
              rules="required"
              name="identity[name]"
              :placeholder="$t('fields.name.label')"
              :label="$t('fields.name.label')" />
          </div>

          <div class="half">
            <KInput
              v-model="identity.alternateName"
              name="identity[alternateName]"
              :placeholder="$t('fields.alternateName.placeholder')"
              :label="$t('fields.alternateName.label')" />
          </div>
        </div>

        <div class="row">
          <div class="half">
            <KInput
              v-model="identity.email"
              name="identity[email]"
              :placeholder="$t('fields.email.placeholder')"
              :label="$t('fields.email.label')" />
          </div>
          <div class="half">
            <KInput
              v-model="identity.phone"
              name="identity[phone]"
              :placeholder="$t('fields.phone.placeholder')"
              :label="$t('fields.phone.label')" />
          </div>
        </div>

        <KInput
          v-model="identity.address"
          name="identity[address]"
          :placeholder="$t('fields.address.placeholder')"
          :label="$t('fields.address.label')" />

        <KInput
          v-model="identity.address2"
          name="identity[address]"
          :placeholder="$t('fields.address2.placeholder')"
          :label="$t('fields.address2.label')" />

        <KInput
          v-model="identity.address3"
          name="identity[address]"
          :placeholder="$t('fields.address3.placeholder')"
          :label="$t('fields.address3.label')" />

        <div class="row">
          <div class="third">
            <KInput
              v-model="identity.zipcode"
              name="identity[zipcode]"
              :placeholder="$t('fields.zipcode.placeholder')"
              :label="$t('fields.zipcode.label')" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.city"
              name="identity[city]"
              :placeholder="$t('fields.city.placeholder')"
              :label="$t('fields.city.label')" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.country"
              name="identity[country]"
              :placeholder="$t('fields.country.placeholder')"
              :label="$t('fields.country.label')" />
          </div>
        </div>

        <div class="row">
          <div class="third">
            <KInput
              v-model="identity.titlePrefix"
              name="identity[titlePrefix]"
              :placeholder="$t('fields.titlePrefix.placeholder')"
              :label="$t('fields.titlePrefix.label')" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.title"
              name="identity[title]"
              :placeholder="$t('fields.title.placeholder')"
              :label="$t('fields.title.label')" />
          </div>
          <div class="third">
            <KInput
              v-model="identity.titlePostfix"
              name="identity[titlePostfix]"
              :placeholder="$t('fields.titlePostfix.placeholder')"
              :label="$t('fields.titlePostfix.label')" />
          </div>
        </div>

        <div class="row">
          <div class="half">
            <KInputImage
              v-model="identity.logo"
              small
              name="identity[logo]"
              preview-key="xlarge"
              :label="$t('fields.logo.label')" />
          </div>
        </div>

        <KInputTable
          v-model="identity.links"
          :new-entry-template="{ name: '', url: '' }"
          :edit-rows="true"
          name="user[links]"
          :label="$t('fields.links.label')">
          <template #head>
            <tr>
              <th>{{ $t('name') }}</th>
              <th>{{ $t('url') }}</th>
              <th></th>
            </tr>
          </template>
          <template #row="{ entry }">
            <td>
              {{ entry.name }}
            </td>
            <td>
              {{ entry.url }}
            </td>
          </template>
          <template #new="{ newEntry }">
            <td>
              <KInput
                v-model="newEntry.name"
                compact
                :placeholder="$t('link-name')"
                name="newLink[name]" />
            </td>
            <td>
              <KInput
                v-model="newEntry.url"
                compact
                :placeholder="$t('link-url')"
                name="newLink[url]" />
            </td>
          </template>
          <template #edit="{ editEntry }">
            <td>
              <KInput
                v-model="editEntry.name"
                compact
                :placeholder="$t('link-name')"
                name="editLink[name]" />
            </td>
            <td>
              <KInput
                v-model="editEntry.url"
                compact
                :placeholder="$t('link-url')"
                name="editLink[url]" />
            </td>
          </template>
        </KInputTable>

        <KInputTable
          v-model="identity.metas"
          :new-entry-template="{ key: '', value: '' }"
          name="user[metas]"
          :label="$t('fields.metas.label')">
          <template #head>
            <tr>
              <th>{{ $t('key') }}</th>
              <th>{{ $t('value') }}</th>
              <th></th>
            </tr>
          </template>
          <template #row="{ entry }">
            <td>
              {{ entry.key }}
            </td>
            <td>
              {{ entry.value }}
            </td>
          </template>
          <template #new="{ newEntry }">
            <td>
              <KInput
                v-model="newEntry.key"
                compact
                :placeholder="$t('meta-key')"
                name="newLink[key]" />
            </td>
            <td>
              <KInput
                v-model="newEntry.value"
                compact
                :placeholder="$t('meta-value')"
                name="newLink[value]" />
            </td>
          </template>
        </KInputTable>
      </template>
    </KForm>
  </div>
</template>

<script>
import gql from 'graphql-tag'
import GET_IDENTITY from '../../gql/identity/IDENTITY_QUERY.graphql'

export default {
  data () {
    return {
      loading: 0,
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

  async created () {
    this.loading++
    this.loading--
  },

  methods: {
    async save () {
      const params = this.$utils.stripParams(this.identity, ['__typename', 'id', 'languages', 'config', 'defaultLanguage'])
      this.$utils.validateImageParams(params, ['logo'])

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
              }
            }
          `,
          variables: {
            identityParams: params
          }
        })

        this.$toast.success({ message: this.$t('updated') })
        this.$router.push({ name: 'dashboard' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    identity: {
      query: GET_IDENTITY,
      fetchPolicy: 'no-cache'
    }
  }
}
</script>
<i18n>
  {
    "en": {
      "title": "Configuration",
      "subtitle": "Identity",
      "help": "Setup for identity and SEO/JSONLD.",
      "back-to-dashboard": "Back to dashboard",
      "organization": "Organization",
      "corporation": "Corporation",
      "name": "Name",
      "url": "URL",
      "key": "Key",
      "value": "Value",
      "updated": "Identity updated",
      "link-name": "Link name",
      "link-url": "https://address.com",
      "meta-key": "META key",
      "meta-value": "Value",
      "fields": {
        "type": {"label": "Type"},
        "name": {"label": "Name"},
        "alternateName": {"label": "Name, short form", "placeholder": "AB"},
        "email": {"label": "Email", "placeholder": "my@email.com"},
        "phone": {"label": "Phone", "placeholder": "+47 900 00 000"},
        "address": {"label": "Address", "placeholder": "Address"},
        "address2": {"label": "Address 2", "placeholder": "Address 2"},
        "address3": {"label": "Address 3", "placeholder": "Address 3"},
        "zipcode": {"label": "Zipcode", "placeholder": "0578"},
        "city": {"label": "City", "placeholder": "Oslo"},
        "country": {"label": "Country", "placeholder": "NO"},
        "titlePrefix": {"label": "Title prefix", "placeholder": "AB | "},
        "title": {"label": "Title (fallback)", "placeholder": "Tittel"},
        "titlePostfix": {"label": "Title postfix", "placeholder": " | AB"},
        "logo": {"label": "Logo"},
        "links": {"label": "Links (social media)"},
        "metas": {"label": "META variables"}
      }
    },
    "no": {
      "title": "Konfigurasjon",
      "subtitle": "Identitet",
      "help": "Konfigurasjon av virksomhetens identitet og SEO/JSONLD.",
      "back-to-dashboard": "Back to dashboard",
      "organization": "Organisasjon",
      "corporation": "Bedrift",
      "name": "Navn",
      "url": "URL",
      "key": "Nøkkel",
      "value": "Verdi",
      "updated": "Identitet oppdatert",
      "link-name": "Lenkenavn",
      "link-url": "https://adresse.no",
      "meta-key": "META nøkkel",
      "meta-value": "Verdi",
      "fields": {
        "type": {"label": "Type"},
        "name": {"label": "Navn"},
        "alternateName": {"label": "Kortere form av navnet", "placeholder": "AB"},
        "email": {"label": "Epost", "placeholder": "min@epost.no"},
        "phone": {"label": "Telefon", "placeholder": "+47 900 00 000"},
        "address": {"label": "Adresse", "placeholder": "Adresse"},
        "address2": {"label": "Adresse 2", "placeholder": "Adresse 2"},
        "address3": {"label": "Adresse 3", "placeholder": "Adresse 3"},
        "zipcode": {"label": "Postnr", "placeholder": "0578"},
        "city": {"label": "Poststed", "placeholder": "Oslo"},
        "country": {"label": "Land", "placeholder": "NO"},
        "titlePrefix": {"label": "Tittel prefiks", "placeholder": "AB | "},
        "title": {"label": "Hovedtittel (fallback)", "placeholder": "Tittel"},
        "titlePostfix": {"label": "Tittel postfiks", "placeholder": " | AB"},
        "logo": {"label": "Logo"},
        "links": {"label": "Linker (sosiale medier)"},
        "metas": {"label": "META variabler"}
      }
    }
  }
</i18n>
