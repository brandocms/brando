<template>
  <article v-if="imageCategory">
    <ContentHeader>
      <template v-slot:title>
        Bildekategori
      </template>
      <template v-slot:subtitle>
        "<span class="cap">{{ imageCategory.name }}</span>"
      </template>
      <template v-slot:help>
        <div>
          <Dropdown>
            <template v-slot:default>
              Handlinger
            </template>
            <template v-slot:content>
              <li>
                <button
                  @click.prevent="createImageCategory">
                  Opprett ny bildekategori
                </button>
              </li>
              <li>
                <button
                  @click.prevent="createImageSeries">
                  Opprett ny bildeserie
                </button>
              </li>
              <li>
                <router-link
                  :to="{ name: 'image-category-edit', params: { categoryId: imageCategory.id } }">
                  Konfigurér bildekategorien
                </router-link>
              </li>
              <li>
                <button
                  @click.prevent="duplicateImageCategory">
                  Dupliser bildekategori
                </button>
              </li>
              <li>
                <button
                  @click.prevent="deleteCategory">
                  Slett bildekategori
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

      <div class="row">
        <div class="col-md-12">
          <transition-group
            name="slide-fade-top-slow"
            appear>
            <ImageSeries
              v-for="s in imageCategory.image_series"
              :key="s.id"
              :image-series="s"
              :selected-images="selectedImages"
              @delete="removeSeries" />
          </transition-group>
          <div v-if="imageCategory.image_series.length">
            <button
              v-if="queryVars.imageSeriesOffset !== 0"
              class="btn btn-outline-secondary"
              @click.prevent="previousPage">
              &larr; Forrige side
            </button>
            <button
              v-if="queryVars.imageSeriesOffset + queryVars.imageSeriesLimit < imageCategory.image_series_count"
              class="btn btn-outline-secondary"
              @click.prevent="nextPage">
              Neste side &rarr;
            </button>
          </div>
        </div>
      </div>
    </div>
  </article>
</template>

<script>
import GET_IMAGE_CATEGORY from '../../gql/images/IMAGE_CATEGORY_QUERY.graphql'
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
      queryVars: {
        imageSeriesOffset: 0,
        imageSeriesLimit: 20
      }
    }
  },

  methods: {
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
      this.$alerts.alertConfirm('OBS', 'Er du sikker på at du vil slette denne bildekategorien?', (data) => {
        if (!data) {
          return
        }

        this.deleteImageCategory(this.imageCategory)
        this.$router.push({ name: 'images' })
      })
    },

    addSeries ({ series, categoryId }) {
      cache.addSeries(this.$apolloProvider, series, categoryId)
    },

    removeSeries (series) {
      cache.removeSeries(this.$apolloProvider, series)
    },

    removeDeletedImage ({ id, imageSeriesId }) {
      const query = {
        query: GET_IMAGE_CATEGORY,
        variables: {
          categoryId: this.imageCategoryId
        }
      }

      const store = this.$apolloProvider.defaultClient.store.cache
      const data = store.readQuery(query)

      const series = data.imageCategory.image_series.find(s => parseInt(s.id) === parseInt(imageSeriesId))
      const idx = series.images.findIndex(i => parseInt(i.id) === parseInt(id))

      if (idx !== -1) {
        series.images.splice(idx, 1)

        store.writeQuery({
          ...query,
          data
        })
      }
    }
  },

  apollo: {
    imageCategory: {
      query: GET_IMAGE_CATEGORY,
      variables () {
        return {
          categoryId: this.imageCategoryId
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
