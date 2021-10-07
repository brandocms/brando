<template>
  <KForm
    v-if="menu && GLOBALS.identity"
    :back="{ name: 'navigation' }"
    @save="save">
    <section class="row">
      <div class="sized">
        <KInputStatus
          v-model="menu.status"
          name="menu[status]"
          rules="required"
          label="Status" />

        <KInput
          v-model="menu.title"
          label="Tittel"
          rules="required"
          placeholder="Tittel"
          name="menu[title]" />

        <KInput
          v-model="menu.key"
          rules="required"
          name="menu[key]"
          type="text"
          label="Nøkkel"
          placeholder="Nøkkel" />

        <KInputSelect
          v-model="menu.language"
          rules="required"
          :options="GLOBALS.identity.languages"
          option-value-key="id"
          name="menu[language]"
          label="Språk" />
      </div>
    </section>
  </KForm>
</template>

<script>
export default {

  inject: [
    'adminChannel',
    'GLOBALS'
  ],

  props: {
    menu: {
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
    }
  }
}
</script>

<style>

</style>
