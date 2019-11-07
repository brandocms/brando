<template>
  <modal
    v-if="showModal"
    :chrome="false"
    :show="showModal"
    :large="true"
    @cancel="closeModal"
    @ok="closeModal">
    <div class="card mb-3">
      <div class="card-header text-center">
        <h5 class="section mb-0">
          Sortér bildeserie
        </h5>
      </div>
      <div class="card-body">
        <transition-group
          v-sortable="{handle: '.sort-handle', animation: 0, store: {get: getOrder, set: storeOrder}}"
          name="fade-move"
          tag="div"
          class="sort-container">
          <div
            v-for="i in imageSeries.images"
            :key="i.id"
            :data-id="i.id"
            class="sort-handle">
            <img :src="i.image.sizes.thumb">
          </div>
        </transition-group>
        <div class="mt-4">
          <button
            class="btn btn-secondary"
            @click.prevent="save">
            Lagre rekkefølge
          </button>
          <button
            class="btn"
            @click.prevent="closeModal">
            Avbryt
          </button>
        </div>
      </div>
    </div>
  </modal>
</template>

<script>
import { mapActions } from 'vuex'
import Modal from '../../Modal.vue'

export default {
  components: {
    Modal
  },

  props: {
    showModal: {
      type: Boolean,
      default: false
    },

    imageSeries: {
      type: Object,
      required: true
    },

    sequenceCallback: {
      type: Function,
      default: null
    }
  },

  data () {
    return {
      sortedArray: []
    }
  },

  inject: [
    'adminChannel'
  ],

  methods: {
    async save () {
      this.adminChannel.channel
        .push('images:sequence_images', { ids: this.sortedArray })
        .receive('ok', payload => {
          this.closeModal()
          if (this.sequenceCallback) {
            this.sequenceCallback({ imageSeries: this.imageSeries, ids: this.sortedArray })
          } else {
            this.sequenceImages({ imageSeries: this.imageSeries, ids: this.sortedArray })
          }
        })
    },

    closeModal () {
      this.$emit('close')
    },

    getOrder (sortable) {
      return this.imageSeries.images
    },

    storeOrder (sortable) {
      this.sortedArray = sortable.toArray()
    },

    ...mapActions('images', [
      'sequenceImages'
    ])
  }
}
</script>
