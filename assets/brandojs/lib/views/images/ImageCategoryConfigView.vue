<template>
  <transition
    name="fade"
    appear>
    <spinner v-if="loading" />
    <div
      v-if="!loading"
      class="card mt-5">
      <div class="card-header">
        <h5 class="section mb-0">
          Konfigurer bildekategori &rarr; {{ currentImageCategory.name }}
        </h5>
      </div>
      <div class="card-body">
        <ImageConfigForm
          :config="config"
          @save="save" />
      </div>
    </div>
  </transition>
</template>

<script>
import { mapActions, mapGetters } from 'vuex'
import nprogress from 'nprogress'
import ImageConfigForm from '../../components/images/ImageConfigForm.vue'

export default {
  components: {
    ImageConfigForm
  },

  props: {
    categoryId: {
      required: true,
      type: String
    }
  },

  data () {
    return {
      loading: 0,
      config: {}
    }
  },

  inject: [
    'adminChannel'
  ],

  computed: {
    ...mapGetters('images', [
      'currentImageCategory'
    ])
  },

  async created () {
    this.loading++
    await this.getData()
    this.adminChannel.channel
      .push('images:get_category_config', { category_id: this.currentImageCategory.id })
      .receive('ok', payload => {
        this.config = payload.config
        this.loading--
      })
  },

  methods: {
    save (config) {
      this.adminChannel.channel
        .push('images:update_category_config', { category_id: this.currentImageCategory.id, config: config })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Konfigurasjon oppdatert' })
          this.$router.push({ name: 'image-category-detail', params: { categoryId: this.currentImageCategory.id } })
        })
    },

    async getData () {
      this.loading++
      nprogress.start()
      await this.fetchImageCategory({ categoryId: this.categoryId, queryVars: this.queryVars })
      this.loading--
      nprogress.done()
    },

    ...mapActions('images', [
      'fetchImageCategory'
    ])
  }
}
</script>
