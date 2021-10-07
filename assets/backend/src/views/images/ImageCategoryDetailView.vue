<template>
  <article v-if="imageCategory">
    <ContentHeader>
      <template #title>
        Bildekategori
      </template>
      <template #subtitle>
        &laquo;<span class="cap">{{ imageCategory.name }}</span>&raquo;
      </template>
      <template #help>
        <div>
          <Dropdown>
            <template #default>
              Handlinger
            </template>
            <template #content>
              <li>
                <button
                  @click.prevent="createImageCategory">
                  Ny kategori
                </button>
              </li>
              <li>
                <button
                  @click.prevent="createImageSeries">
                  Ny serie
                </button>
              </li>
              <li>
                <router-link
                  :to="{ name: 'image-category-edit', params: { categoryId: imageCategory.id } }">
                  Konfigurér kategorien
                </router-link>
              </li>
              <li>
                <button
                  @click.prevent="propagateConfigToSeries">
                  Forplant konfigurasjon til alle serier
                </button>
              </li>
              <li>
                <button
                  @click.prevent="duplicateImageCategory">
                  Dupliser kategori
                </button>
              </li>
              <li>
                <button
                  @click.prevent="deleteCategory">
                  Slett kategori
                </button>
              </li>
            </template>
          </Dropdown>
        </div>
      </template>
    </ContentHeader>

    <div
      v-if="imageCategory"
      class="image-category-detail">
      <ImageSelection
        :selected-images="selectedImages"
        @delete="removeDeletedImage" />
      <div class="row">
        <div class="col-md-12">
          <ModalCreateImageSeries
            v-if="showModalImageCreateSeries"
            :image-category="imageCategory"
            @save="addSeries"
            @close="closeCreateImageSeriesModal" />
          <ModalCreateImageCategory
            :show-modal="showModalImageCreateCategory"
            @close="closeCreateImageCategoryModal" />
          <ModalDuplicateImageCategory
            :show-modal="showModalImageDuplicateCategory"
            :cat="imageCategory"
            @close="closeDuplicateImageCategoryModal" />
        </div>
      </div>

      <div>
        <div>
          <transition-group
            name="slide-fade-top-slow"
            appear>
            <ImageSeries
              v-for="s in imageCategory.imageSeries"
              :key="s.id"
              :image-series="s"
              :selected-images="selectedImages"
              @delete="removeSeries" />
          </transition-group>
          <div v-if="imageCategory.imageSeries.length">
            <ButtonSecondary
              v-if="limit * page < imageCategory.imageSeriesCount"
              @click="nextPage">
              Last inn flere
            </ButtonSecondary>
          </div>
        </div>
      </div>
    </div>
  </article>
</template>

<script>
import GET_IMAGE_CATEGORY from '../../gql/images/IMAGE_CATEGORY_QUERY.graphql'
import DELETE_IMAGE_CATEGORY from '../../gql/images/DELETE_IMAGE_CATEGORY.graphql'
import cache from './cache'

import ImageSeries from '../../components/images/ImageSeries'
// import ImageSelection from '../../components/images/ImageSelection'
import ModalCreateImageSeries from '../../components/images/modals/ModalCreateImageSeries'
import ModalCreateImageCategory from '../../components/images/modals/ModalCreateImageCategory'
import ModalDuplicateImageCategory from '../../components/images/modals/ModalDuplicateImageCategory'

export default {
  components: {
    // ImageSelection,
    ImageSeries,
    ModalCreateImageSeries,
    ModalCreateImageCategory,
    ModalDuplicateImageCategory
  },

  inject: [
    'adminChannel'
  ],

  props: {
    imageCategoryId: {
      required: true,
      type: Number
    }
  },

  data () {
    return {
      showModalImageCreateSeries: false,
      showModalImageCreateCategory: false,
      showModalImageDuplicateCategory: false,
      selectedImages: [],
      loading: 0,
      page: 0,
      limit: 100
    }
  },

  methods: {
    nextPage () {
      this.page++
    },

    propagateConfigToSeries () {
      this.adminChannel.channel
        .push('images:propagate_category_config', { category_id: this.imageCategory.id })
        .receive('ok', payload => {
          this.$toast.success({ message: 'Konfigurasjon forplantet til alle serier.' })
        })
    },

    createImageSeries () {
      this.showModalImageCreateSeries = true
    },

    createImageCategory () {
      this.showModalImageCreateCategory = true
    },

    duplicateImageCategory (cat) {
      this.showModalImageDuplicateCategory = true
    },

    closeCreateImageSeriesModal () {
      this.showModalImageCreateSeries = false
    },

    closeCreateImageCategoryModal () {
      this.showModalImageCreateCategory = false
    },

    closeDuplicateImageCategoryModal () {
      this.showModalImageDuplicateCategory = false
    },

    deleteCategory () {
      this.$alerts.alertConfirm('OBS', 'Er du sikker på at du vil slette denne bildekategorien?', async data => {
        if (!data) {
          return
        }

        try {
          await this.$apollo.mutate({
            mutation: DELETE_IMAGE_CATEGORY,

            variables: {
              imageCategoryId: this.imageCategory.id
            }
          })

          this.$toast.success({ message: 'Slettet kategori' })
          this.$router.push({ name: 'images' })
        } catch (err) {
          this.$utils.showError(err)
        }
      })
    },

    addSeries ({ series, categoryId }) {
      cache.addSeries(this.$apolloProvider, series, categoryId)
    },

    removeSeries (series) {
      cache.removeSeries(this.$apolloProvider, series)
    },

    removeDeletedImage ({ id, imageSeriesId }) {
      this.$apollo.queries.imageCategory.refresh()
    }
  },

  apollo: {
    imageCategory: {
      query: GET_IMAGE_CATEGORY,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          categoryId: this.imageCategoryId,
          imageSeriesOffset: this.limit * this.page
        }
      },

      skip () {
        return !this.imageCategoryId
      }
    }
  }

}
</script>

<style lang="postcss" scoped>

</style>
