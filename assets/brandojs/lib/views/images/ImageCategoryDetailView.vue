<template>
  <transition
    name="fade"
    appear>
    <spinner v-if="loading" />
    <div
      v-if="!loading"
      class="image-category-detail">
      <ImageSelection
        :selected-images="selectedImages" />
      <div class="row">
        <div class="col-md-12">
          <h1 class="wide text-center">
            {{ currentImageCategory.name }}
            <b-dropdown
              variant="white btn-lg ml-3"
              no-caret>
              <template slot="button-content">
                <i class="k-dropdown-icon" />
              </template>
              <button
                class="dropdown-item"
                @click.prevent="createImageCategory">
                <i class="fal fa-fw mr-3 subtle fa-plus-circle" />
                Opprett ny bildekategori
              </button>
              <button
                class="dropdown-item"
                @click.prevent="createImageSeries">
                <i class="fal fa-fw mr-3 subtle fa-plus" />
                Opprett ny bildeserie
              </button>
              <button
                class="dropdown-item"
                disabled>
                <i class="fal fa-fw mr-3 subtle fa-sort-amount-down" />
                Sortér bildeserier i kategorien
              </button>
              <button
                class="dropdown-item"
                disabled>
                <i class="fal fa-fw mr-3 subtle fa-sync" />
                Gjenskap bilder i kategorien
              </button>
              <router-link
                :to="{ name: 'image-category-config', params: { categoryId: currentImageCategory.id } }"
                tag="button"
                class="dropdown-item">
                <i class="fal fa-fw mr-3 subtle fa-cog" />
                Konfigurér bildekategorien
              </router-link>
              <button
                class="dropdown-item"
                @click.prevent="duplicateImageCategory">
                <i class="fal fa-fw mr-3 subtle fa-clone" />
                Dupliser bildekategori
              </button>
              <button
                class="dropdown-item"
                @click.prevent="deleteCategory">
                <i class="fal fa-fw mr-3 subtle fa-trash" />
                Slett bildekategori
              </button>
            </b-dropdown>
          </h1>

          <ModalCreateImageSeries
            v-if="showModalImageCreateSeries"
            :image-category="currentImageCategory"
            @close="closeCreateImageSeriesModal" />
          <ModalCreateImageCategory
            :show-modal="showModalImageCreateCategory"
            @close="closeCreateImageCategoryModal" />
          <ModalDuplicateImageCategory
            :show-modal="showModalImageDuplicateCategory"
            :cat="currentImageCategory"
            @close="closeDuplicateImageCategoryModal" />
        </div>
      </div>

      <div class="row">
        <div class="col-md-12">
          <transition-group
            name="slide-fade-top-slow"
            appear>
            <ImageSeries
              v-for="s in currentImageCategory.image_series"
              :key="s.id"
              :image-series="s"
              :selected-images="selectedImages" />
          </transition-group>
          <div v-if="currentImageCategory.image_series.length">
            <button
              v-if="queryVars.imageSeriesOffset !== 0"
              class="btn btn-outline-secondary"
              @click.prevent="previousPage">
              &larr; Forrige side
            </button>
            <button
              v-if="queryVars.imageSeriesOffset + queryVars.imageSeriesLimit < currentImageCategory.image_series_count"
              class="btn btn-outline-secondary"
              @click.prevent="nextPage">
              Neste side &rarr;
            </button>
          </div>
        </div>
      </div>
    </div>
  </transition>
</template>

<script>
import { mapActions, mapGetters } from 'vuex'
import nprogress from 'nprogress'
import { alertConfirm } from '../../utils/alerts'

import ImageSeries from '../../components/images/ImageSeries'
import ImageSelection from '../../components/images/ImageSelection'
import ModalCreateImageSeries from '../../components/images/modals/ModalCreateImageSeries'
import ModalCreateImageCategory from '../../components/images/modals/ModalCreateImageCategory'
import ModalDuplicateImageCategory from '../../components/images/modals/ModalDuplicateImageCategory'

export default {
  components: {
    ImageSelection,
    ImageSeries,
    ModalCreateImageSeries,
    ModalCreateImageCategory,
    ModalDuplicateImageCategory
  },

  props: {
    categoryId: {
      required: false,
      type: String,
      default: ''
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

  computed: {
    ...mapGetters('images', [
      'currentImageCategory'
    ])
  },

  created () {
    this.getData()
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

    async getData () {
      this.loading++
      nprogress.start()
      await this.fetchImageCategory({ categoryId: this.categoryId, queryVars: this.queryVars })
      this.loading--
      nprogress.done()
    },

    deleteCategory () {
      alertConfirm('OBS', 'Er du sikker på at du vil slette denne bildekategorien?', (data) => {
        if (!data) {
          return
        }

        this.deleteImageCategory(this.currentImageCategory)
        this.$router.push({ name: 'images' })
      })
    },

    nextPage () {
      this.queryVars.imageSeriesOffset = this.queryVars.imageSeriesOffset + this.queryVars.imageSeriesLimit
      this.getData()
    },

    previousPage () {
      if (this.queryVars.imageSeriesOffset >= this.queryVars.imageSeriesLimit) {
        this.queryVars.imageSeriesOffset = this.queryVars.imageSeriesOffset - this.queryVars.imageSeriesLimit
        this.getData()
      }
    },

    ...mapActions('images', [
      'fetchImageCategory',
      'deleteImageCategory'
    ])
  }
}
</script>

<style lang="css">
</style>
