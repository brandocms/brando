<template>
  <KForm
    v-if="imageCategory"
    :back="{ name: 'images' }"
    @save="save">
    <section class="row">
      <div class="half">
        <KInput
          v-model="imageCategory.name"
          rules="required"
          name="imageCategory[name]"
          type="text"
          label="Tittel"
          placeholder="Tittel" />

        <KInputSlug
          v-model="imageCategory.slug"
          :from="imageCategory.name"
          rules="required"
          label="URL-tamp"
          placeholder="URL-tamp"
          name="imageCategory[slug]" />
      </div>
    </section>

    <ImageConfigForm :config="imageCategory.cfg" />
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
    imageCategory: {
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
