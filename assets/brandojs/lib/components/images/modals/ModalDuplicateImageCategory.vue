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
          Duplisér bildekategori
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
        <KInputSlug
          v-model="category.slug"
          rules="required"
          :from="category.name"
          :value="category.slug"
          name="category[slug]"
          label="Kategoriens URL-tamp"
          placeholder="Kategoriens URL-tamp"
          data-vv-name="category[slug]"
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
    },
    cat: {
      type: Object,
      default: () => {}
    }
  },

  data () {
    return {
      category: {
        name: ''
      },
      config: null
    }
  },

  inject: [
    'adminChannel'
  ],

  created () {
    this.category = {
      name: this.cat.name,
      slug: this.cat.slug
    }

    // get the duped category's config
    this.adminChannel.channel
      .push('images:get_category_config', { category_id: this.cat.id })
      .receive('ok', payload => {
        this.config = payload.config
      })
  },

  methods: {
    async save () {
      try {
        const c = await this.createImageCategory(this.category)
        this.adminChannel.channel
          .push('images:update_category_config', { category_id: c.id, config: this.config })
          .receive('ok', payload => {
            this.$toast.success({ message: 'Konfigurasjon oppdatert' })
            this.$router.push({ name: 'image-category-detail', params: { categoryId: c.id } })
          })
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
