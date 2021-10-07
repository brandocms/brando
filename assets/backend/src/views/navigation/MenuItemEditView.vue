<template>
  <article
    v-if="menuItemId"
    :key="menuItemId">
    <ContentHeader>
      <template #title>
        Endre menypunkt
      </template>
    </ContentHeader>
    <MenuItemForm
      :key="menuItemId"
      :menu-item="menuItem"
      :save="save" />
  </article>
</template>

<script>

import GET_MENU_ITEM from '../../gql/navigation/MENU_ITEM_QUERY.graphql'
import gql from 'graphql-tag'
import MenuItemForm from './MenuItemForm'

export default {
  components: {
    MenuItemForm
  },

  props: {
    menuItemId: {
      type: [String, Number],
      required: true
    }
  },

  data () {
    return {
    }
  },

  methods: {
    async save () {
      const menuItemParams = this.$utils.stripParams(
        this.menuItem, [
          '__typename',
          'id',
          'insertedAt',
          'updatedAt',
          'menu',
          'items',
          'creator'
        ])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateMenuItem($menuItemId: ID!, $menuItemParams: MenuItemParams) {
              updateMenuItem(
                menuItemId: $menuItemId,
                menuItemParams: $menuItemParams
              ) {
                id
              }
            }
          `,
          variables: {
            menuItemParams,
            menuItemId: this.menuItem.id
          }
        })

        this.$toast.success({ message: 'Menypunkt oppdatert' })
        this.$router.push({ name: 'navigation' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    menuItem: {
      query: GET_MENU_ITEM,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          menuItemId: this.menuItemId
        }
      },

      skip () {
        return !this.menuItemId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
</style>
