<template>
  <div
    :class="{selected: selected}"
    class="image-wrapper float-left m-1"
    @mouseover="mouseOver"
    @mouseout="mouseOut">
    <div
      v-show="showOverlay"
      class="overlay"
      @click.stop.prevent="editImage">
      <i class="fa fa-search fa-fw" />
    </div>
    <modal
      v-if="showEdit"
      :chrome="false"
      :large="true"
      :show="true"
      @cancel="closeEdit"
      @ok="closeEdit">
      <div class="card">
        <div class="card-header">
          Bildedetaljer
        </div>
        <div class="card-body">
          <div class="row">
            <div class="col-6">
              <FocusPoint v-model="img.image.focal">
                <img
                  :src="'/media/' + img.image.path"
                  class="img-fluid">
              </FocusPoint>

              <div class="row mt-4">
                <div class="col-md-6">
                  <dt>
                    Dimensjoner
                  </dt>
                  <dd v-if="img.image.width && img.image.height">
                    {{ img.image.width }}x{{ img.image.height }}
                  </dd>
                  <dd v-else>
                    Ingen dimensjoner
                  </dd>
                </div>
              </div>
            </div>
            <div class="col-6">
              <KInput
                v-model="img.image.title"
                :value="img.image.title"
                name="img.image[title]"
                label="Evt. beskrivelse"
                placeholder="Evt. beskrivelse"
                data-vv-name="img.image[title]"
                data-vv-value-path="innerValue" />
              <KInput
                v-model="img.image.credits"
                :value="img.image.credits"
                name="img.image[credits]"
                label="Evt. kreditering"
                placeholder="Evt. kreditering"
                data-vv-name="img.image[credits]"
                data-vv-value-path="innerValue" />
              <dt>
                Filnavn
              </dt>
              <dd>
                {{ img.image.path }}
              </dd>

              <button
                class="btn btn-outline-secondary btn-block"
                @click.prevent="saveEdit">
                Lagre
              </button>
              <button
                class="btn btn-outline-secondary btn-block"
                @click.prevent="closeEdit">
                Lukk
              </button>
            </div>
          </div>
        </div>
      </div>
    </modal>

    <img
      :src="img.image.sizes.thumb + '?' + timestamp"
      class="img-fluid"
      @click.stop.prevent="click">
  </div>
</template>

<script>

import moment from 'moment-timezone'
import Modal from '../Modal.vue'
import FocusPoint from './FocusPoint.vue'

import { clone } from '../../utils'

export default {
  components: {
    FocusPoint,
    Modal
  },

  props: {
    image: {
      required: true,
      type: Object
    },

    selectedImages: {
      type: Array,
      required: true,
      default: () => []
    }
  },

  data () {
    return {
      img: {},
      selected: false,
      showEdit: false,
      showOverlay: false
    }
  },

  computed: {
    timestamp () {
      return moment(this.img.updated_at)
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    this.img = clone(this.image)
  },

  methods: {
    mouseOver () {
      this.showOverlay = true
    },

    mouseOut () {
      this.showOverlay = false
    },

    editImage () {
      this.showEdit = true
      this.showOverlay = false
    },

    closeEdit () {
      this.showEdit = false
      this.selected = false
      this.showOverlay = false
    },

    saveEdit () {
      this.adminChannel.channel.push('image:update', this.img)

      this.showEdit = false
      this.selected = false
      this.showOverlay = false
    },

    click (ev) {
      // don't select if modal is open.
      if (!this.showEdit) {
        this.selected = !this.selected
        if (this.selected) {
          this.selectedImages.push(this)
        } else {
          let idx = this.selectedImages.indexOf(this)
          this.selectedImages.splice(idx, 1)
        }
      }
    }
  }
}
</script>
