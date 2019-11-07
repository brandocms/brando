<template>
  <modal
    v-if="show"
    :chrome="false"
    :show="show"
    :large="true"
    @cancel="closeModal"
    @ok="closeModal">
    <div class="card mb-3">
      <div class="card-header text-center">
        <h5 class="section mb-0">
          Velg bilde
        </h5>
      </div>
      <div class="card-body">
        <transition-group
          v-if="imageSeries"
          name="fade-move"
          tag="div">
          <div
            v-for="i in imageSeries.images"
            :key="i.id"
            :data-id="i.id"
            class="float-left"
            @click="selectImage(i)">
            <img :src="i.image.sizes.thumb">
          </div>
        </transition-group>
      </div>
    </div>
  </modal>
</template>
<script>
import { imageAPI } from '../../../api/image'

export default {
  props: {
    show: {
      type: Boolean,
      default: false
    },

    imageSeriesId: {
      type: Number,
      required: true
    },

    value: {
      type: Object,
      default: () => {}
    }
  },

  data () {
    return {
      imageSeries: {}
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    // get imageseries
    this.getData()
  },

  methods: {
    async getData () {
      this.imageSeries = await imageAPI.getImageSeries(this.imageSeriesId)
    },

    selectImage (i) {
      this.adminChannel.channel
        .push('image:get', { id: i.id })
        .receive('ok', payload => {
          this.$emit('change', payload.image)
          this.$emit('close')
        })
    },

    closeModal () {
      this.$emit('close')
    }
  }
}
</script>
