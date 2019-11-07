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
          class="btn"
          @click.prevent="closeModal">
          Avbryt
        </button>
      </div>
    </div>
  </modal>
</template>

<script>
import { imageAPI } from '../../../api/image'
import { mapActions } from 'vuex'
import Modal from '../../Modal.vue'
import { showError } from '../../../utils'

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
        if (this.saveCallback) {
          const series = await imageAPI.createImageSeries({ ...this.series, image_category_id: this.imageCategory.id })
          this.saveCallback(series)
        } else {
          await this.createImageSeries({ ...this.series, image_category_id: this.imageCategory.id })
        }
        // scroll to it?
        this.closeModal()
      } catch (err) {
        showError(err)
      }
    },

    closeModal () {
      this.$emit('close')
    },

    ...mapActions('images', [
      'createImageSeries'
    ])
  }
}
</script>
