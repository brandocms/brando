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

    <p class="help">
      {{ $t('help-more') }}
    </p>

    <table
      v-for="(value, name) in caches"
      :key="name">
      <h1>{{ name }}</h1>
      <tr
        v-for="(entry, idx) in value"
        :key="idx">
        <template v-if="entry[0] === 'list'">
          <td>
            <div class="badge">
              {{ entry[0] }}
            </div>
          </td>
          <td>
            <FontAwesomeIcon
              icon="map-marker-alt"
              size="sm" /> {{ entry[1] }}
          </td>
          <td>
            <FontAwesomeIcon
              icon="key"
              size="sm" /> {{ entry[2] }}
          </td>
          <td></td>
        </template>
        <template v-else-if="entry[0] === 'single'">
          <td>
            <div class="badge">
              {{ entry[0] }}
            </div>
          </td>
          <td>
            <FontAwesomeIcon
              icon="map-marker-alt"
              size="sm" /> {{ entry[1] }}
          </td>
          <td>
            <FontAwesomeIcon
              icon="key"
              size="sm" /> {{ entry[2] }}
          </td>
          <td>{{ entry[3] }}</td>
        </template>
      </tr>
    </table>

    <ButtonPrimary
      @click="emptyCaches">
      {{ $t('empty-caches') }}
    </ButtonPrimary>

    <ButtonPrimary
      @click="refreshCaches">
      {{ $t('refresh-caches') }}
    </ButtonPrimary>
  </div>
</template>

<script>

export default {
  inject: [
    'adminChannel'
  ],

  data () {
    return {
      loading: 0,
      caches: []
    }
  },

  async created () {
    this.loading++
    this.loading--
  },

  mounted () {
    this.refreshCaches()
  },

  methods: {
    emptyCaches () {
      this.$toast.success({ message: this.$t('emptying-caches') })
      this.adminChannel.channel
        .push('cache:empty', {})
        .receive('ok', result => { this.caches = [] })
    },
    refreshCaches () {
      this.$toast.success({ message: this.$t('fetching-caches') })
      this.adminChannel.channel
        .push('cache:list', {})
        .receive('ok', result => { this.caches = result.caches })
    }
  }
}
</script>
<style lang="postcss" scoped>
  .help {
    @column 10/16;
    @space padding-bottom 20px;
  }

  table {
    @column 10/16;
    @space margin-bottom 35px;
    @space margin-top 10px;

    h1 {
      @space margin-bottom 20px;
      text-transform: capitalize;
    }

    td {
      @font mono;
      @fontsize base(0.8);
      border: 1px solid;
      padding: 10px 15px;
    }
  }

  button + button {
    @space margin-left 15px;
  }

</style>
<i18n>
  {
    "en": {
      "title": "Configuration",
      "subtitle": "Cache",
      "help": "Inspect and empty caches",
      "empty-caches": "Empty caches",
      "refresh-caches": "Refresh caches",
      "fetching-caches": "Fetching caches",
      "emptying-caches": "Emptying caches"
    },
    "no": {
      "title": "Konfigurasjon",
      "subtitle": "Hurtigbuffere",
      "help": "Administrér og tøm hurtigbuffere.",
      "help-more": "Hurtigbuffere er som et slags fotografi av dataene dine som vi bruker for å kunne levere de raskere. Om du har endret data og det ikke vises på nettsiden kan du forsøke å tømme hurtigbufferene!",
      "empty-caches": "Tøm hurtigbuffere",
      "refresh-caches": "Oppdater hurtigbufferliste",
      "fetching-caches": "Henter hurtigbufferliste",
      "emptying-caches": "Tømmer hurtigbufferene"
    }
  }
</i18n>
