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
      ref="modal"
      @cancel="closeEdit">
      <div class="card">
        <div class="card-header">
          Bildedetaljer
        </div>
        <div class="card-body">
          <div class="row">
            <div class="half">
              <FocusPoint v-model="img.image.focal">
                <img
                  :src="'/media/' + img.image.path"
                  class="img-fluid">
              </FocusPoint>

              <div class="row info">
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
            <div class="half">
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

              <div class="info">
                <dt>
                  Filnavn
                </dt>
                <dd>
                  {{ img.image.path }}
                </dd>
              </div>

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
    this.img = this.$utils.clone(this.image)
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
      this.$nextTick(() => {
        this.showEdit = false
        this.selected = false
        this.showOverlay = false
      })
    },

    saveEdit () {
      this.adminChannel.channel.push('image:update', this.img)

      this.showEdit = false
      this.selected = false
      this.showOverlay = false
    },

    click (ev) {
      console.log('click')
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

<style lang="postcss" scoped>
.image-wrapper {
  border: 5px solid #000;
  cursor: pointer;
  height: 125px;
  padding: 2px;
  position: relative;
  width: 125px;
  margin: 0.25rem;
  float: left;

  &.sort-handle {
    cursor: move;
  }

  &.selected {
    background-color: theme(colors.overlay);
    border: 3px solid theme(colors.overlay);
    padding: 0;

    img {
      opacity: 0.50;
    }
  }

  .overlay {
    align-items: center;
    background-color: theme(colors.overlay);
    border-radius: 15px;
    display: flex;
    height: 30px;
    justify-content: center;
    opacity: 0.5;
    position: absolute;
    right: 5px;
    top: 5px;
    transition: all 500ms ease;
    width: 30px;

    &:hover {
      opacity: 1;
      transition: all 250ms ease;
    }

    i {
      color: #fff;
      text-align: center;
      transition: all 500ms ease;
    }
  }

  img {
    opacity: 1;
  }
}

.img-border-lg {
  border: 5px solid #000;
}

dt {
  @fontsize sm;
  font-weight: 500;
}

dd {
  @fontsize sm;
}

.info {
  @space margin-y xs;
}

.btn-outline-secondary {
  @fontsize base;
  height: 60px;

  + .btn-outline-secondary {
    margin-top: -1px;
  }
}

</style>
