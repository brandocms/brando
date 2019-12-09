<template>
  <modal
    :chrome="false"
    :show="true"
    @cancel="closeModal"
    @ok="closeModal">
    <div class="card mb-3">
      <div class="card-header text-center">
        <h5 class="section mb-0">
          Ny bildeserie
        </h5>
      </div>
      <div class="card-body">
        <KInput
          v-model="series.name"
          rules="required"
          :value="series.name"
          name="series[name]"
          label="Seriens navn"
          placeholder="Seriens navn"
          data-vv-name="series[name]"
          data-vv-value-path="innerValue" />
        <KInput
          v-model="series.credits"
          :value="series.credits"
          name="series[credits]"
          label="Evt. krediteringer"
          placeholder="Evt. krediteringer"
          data-vv-name="series[credits]"
          data-vv-value-path="innerValue" />

        <button
          class="btn btn-secondary"
          @click.prevent="save">
          Lagre bildeserie
        </button>
        <button
          class="btn btn-secondary"
          @click.prevent="closeModal">
          Avbryt
        </button>
      </div>
    </div>
  </modal>
</template>

<script>
import Modal from '../../Modal'
import gql from 'graphql-tag'

export default {
  components: {
    Modal
  },

  props: {
    showModal: {
      type: Boolean,
      default: false
    },

    imageCategory: {
      type: Object,
      required: true
    },

    saveCallback: {
      type: Function,
      default: null
    }
  },

  data () {
    return {
      series: {
        name: '',
        credits: ''
      }
    }
  },

  methods: {
    async save () {
      try {
        const imageSeriesParams = { ...this.series, imageCategoryId: this.imageCategory.id }
        const result = await this.$apollo.mutate({
          mutation: gql`
            mutation CreateImageSeries($imageSeriesParams: ImageSeriesParams) {
              createImageSeries(
                imageSeriesParams: $imageSeriesParams,
              ) {
                id
                name
                slug
                image_category_id

                images {
                  id

                  image {
                    path
                    credits
                    title
                    focal
                    width
                    height
                    sizes
                    thumb: url(size: "thumb")
                    medium: url(size: "medium")
                  }

                  image_series_id
                  sequence
                  updated_at
                  deleted_at
                }
              }
            }
          `,
          variables: {
            imageSeriesParams
          }
        })

        this.$emit('save', { categoryId: this.imageCategory.id, series: result.data.createImageSeries })
        this.closeModal()
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    closeModal () {
      this.$emit('close')
    }
  }
}
</script>
