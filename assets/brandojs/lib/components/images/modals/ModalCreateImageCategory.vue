<template>
  <modal
    v-if="showModal"
    :chrome="false"
    :show="showModal"
    @cancel="closeModal"
    @ok="closeModal">
    <div class="card mb-3">
      <div class="card-header text-center">
        <h5 class="section mb-0">
          Ny bildekategori
        </h5>
      </div>
      <div class="card-body">
        <KInput
          v-model="category.name"
          rules="required"
          :value="category.name"
          name="category[name]"
          label="Kategoriens navn"
          placeholder="Kategoriens navn"
          data-vv-name="category[name]"
          data-vv-value-path="innerValue" />
        <button
          class="btn btn-secondary"
          @click.prevent="save">
          Lagre bildekategori
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
    }
  },

  data () {
    return {
      category: {
        name: ''
      }
    }
  },

  methods: {
    async save () {
      try {
        const c = await this.createImageCategory(this.category)
        this.$router.push({ name: 'image-category-detail', params: { categoryId: c.id } })
      } catch (err) {
        showError(err)
      }
    },

    closeModal () {
      this.$emit('close')
    },

    ...mapActions('images', [
      'createImageCategory'
    ])
  }
}
</script>
