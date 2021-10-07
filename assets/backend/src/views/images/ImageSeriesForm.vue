<template>
  <KForm
    v-if="imageSeries"
    :back="{ name: 'images' }"
    @save="save">
    <section class="row">
      <div class="half">
        <KInput
          v-model="imageSeries.name"
          rules="required"
          name="imageSeries[name]"
          type="text"
          label="Tittel"
          placeholder="Tittel" />

        <KInputSlug
          v-model="imageSeries.slug"
          :from="imageSeries.name"
          rules="required"
          label="URL-tamp"
          placeholder="URL-tamp"
          name="imageSeries[slug]" />
      </div>
    </section>

    <ImageConfigForm :config="imageSeries.cfg" />
  </KForm>
</template>

<script>

import ImageConfigForm from './ImageConfigForm'

export default {
  components: {
    ImageConfigForm
  },

  inject: [
    'adminChannel'
  ],

  props: {
    imageSeries: {
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
  },

  created () {
  }
}
</script>

<style>

</style>
