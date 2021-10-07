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
          class="btn btn-secondary"
          @click.prevent="closeModal">
          Avbryt
        </button>
      </div>
    </div>
  </modal>
</template>

<script>
import gql from 'graphql-tag'
import Modal from '../../Modal.vue'

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
        await this.$apollo.mutate({
          mutation: gql`
              mutation CreateImageCategory($imageCategoryParams: ImageCategoryParams) {
                createImageCategory(
                  imageCategoryParams: $imageCategoryParams
                ) {
                  id
                }
              }
            `,
          variables: {
            imageCategoryParams: this.category
          },
          update: (store, { data: { createImageCategory } }) => {
            this.$toast.success({ message: 'Kategori opprettet' })
            this.$router.push({ name: 'image-category-detail', params: { categoryId: createImageCategory.id } })
          }
        })
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
