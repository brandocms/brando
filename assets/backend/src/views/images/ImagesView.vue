<template>
  <article class="images">
    <ContentHeader>
      <template #title>
        Bildebibliotek
      </template>
      <template #subtitle>
        Administrasjon
      </template>
      <template #help>
        <p>
          Administrasjon av nettsidens bilder, bildeserier og bildekategorier.
        </p>
      </template>
    </ContentHeader>
    <template v-if="imageCategories && imageCategories.length">
      <ContentList
        :entries="imageCategories">
        <template #row="{ entry }">
          <div class="col-11">
            <router-link
              :to="{ name: 'image-category-detail', params: { imageCategoryId: entry.id } }">
              <span class="name">{{ entry.name }}</span>
            </router-link><br>
            <span class="small">
              <strong>{{ entry.imageSeriesCount }}</strong> bildeserie(r) i denne kategorien
            </span>
          </div>
          <div class="col-4">
            <ItemMeta
              :entry="entry"
              :user="entry.creator" />
          </div>
          <div class="col-1">
            <CircleDropdown>
              <li>
                <router-link :to="{ name: 'image-category-edit', params: { imageCategoryId: entry.id } }">
                  Endre kategori
                </router-link>
              </li>
            </CircleDropdown>
          </div>
        </template>
      </ContentList>
    </template>
  </article>
</template>

<script>

import GET_CATEGORIES from '../../gql/images/IMAGE_CATEGORIES_QUERY.graphql'

export default {
  apollo: {
    imageCategories: {
      query: GET_CATEGORIES
    }
  }
}
</script>

<style lang="postcss" scoped>
  .name {
    text-transform: capitalize;
  }

  .small {
    @fontsize sm;
    strong {
      font-weight: 500;
    }
  }
</style>
