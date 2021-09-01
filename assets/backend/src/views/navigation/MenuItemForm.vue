<template>
  <KForm
    v-if="menuItem"
    :back="false"
    @save="save">
    <KInputStatus
      v-model="menuItem.status"
      name="menuItem[status]"
      rules="required"
      label="Status" />

    <KInputToggle
      v-model="menuItem.openInNewWindow"
      name="menuItem[openInNewWindow]"
      label="Åpne i nytt vindu" />

    <KInput
      v-model="menuItem.title"
      label="Tittel"
      rules="required"
      placeholder="Tittel"
      name="menuItem[title]" />

    <KInput
      v-model="menuItem.key"
      rules="required"
      name="menuItem[key]"
      type="text"
      label="Nøkkel"
      placeholder="Nøkkel" />

    <KInput
      v-model="menuItem.url"
      rules="required"
      name="menuItem[key]"
      label="URL"
      placeholder="/side" />
  </KForm>
</template>

<script>
export default {

  inject: [
    'adminChannel'
  ],
  props: {
    menuItem: {
      type: Object,
      default: () => {}
    },

    save: {
      type: Function,
      required: true
    }
  },

  data () {
    return {}
  }
}
</script>

<style>

</style>
