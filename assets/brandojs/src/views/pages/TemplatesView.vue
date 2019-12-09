<template>
  <div class="villain-component">
    <ContentHeader>
      <template v-slot:title>
        Innholdsmaler
      </template>
      <template v-slot:subtitle>
        Konfigurasjon
      </template>
      <template v-slot:help>
        <p>
          Opprettelse og oppsett av maler for innholdssider
        </p>
      </template>
    </ContentHeader>
    <VillainEditor
      ref="villain"
      :builder-mode="true"
      :extra-headers="{'authorization': `Bearer ${token}`}"
      @input="$emit('input', $event)" />
  </div>
</template>

<script>
import VillainEditor from '@univers-agency/villain-editor'
import gql from 'graphql-tag'

export default {
  components: {
    VillainEditor
  },

  data () {
    return {
      innerValue: null
    }
  },

  watch: {
    value (value) {
      this.innerValue = value
    }
  },

  created () {
    this.innerValue = this.value
  },

  apollo: {
    token: gql`
      query getToken {
        token @client
      }
    `
  }
}
</script>

<style lang="postcss">
.villain-builder {
  aside .villain-builder-aside-header {
    font-weight: 500;
    text-align: left;
  }

  .villain-builder-content-aside {
    li.text-mono {
      @fontsize sm;
    }
  }

  .villain-builder-block-attributes,
  .villain-builder-block-picker-namer {
    .form-control {
      @fontsize sm;
      padding-top: 9px;
      padding-bottom: 5px;
      padding-left: 15px;
      padding-right: 15px;
      width: 100%;
      background-color: theme(colors.input);
      border: 0;
    }
  }
}
</style>
