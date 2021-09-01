<template>
  <article
    v-if="menuId"
    :key="menuId">
    <ContentHeader>
      <template #title>
        Endre meny
      </template>
    </ContentHeader>
    <MenuForm
      :key="menuId"
      :menu="menu"
      :save="save" />
  </article>
</template>

<script>

import GET_MENU from '../../gql/navigation/MENU_QUERY.graphql'
import gql from 'graphql-tag'
import MenuForm from './MenuForm'

export default {
  components: {
    MenuForm
  },

  props: {
    menuId: {
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
      const menuParams = this.$utils.stripParams(
        this.menu, [
          '__typename',
          'id',
          'insertedAt',
          'updatedAt',
          'items',
          'creator'
        ])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateMenu($menuId: ID!, $menuParams: MenuParams) {
              updateMenu(
                menuId: $menuId,
                menuParams: $menuParams
              ) {
                id
              }
            }
          `,
          variables: {
            menuParams,
            menuId: this.menu.id
          }
        })

        this.$toast.success({ message: 'Meny oppdatert' })
        this.$router.push({ name: 'navigation' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  },

  apollo: {
    menu: {
      query: GET_MENU,
      fetchPolicy: 'no-cache',
      variables () {
        return {
          menuId: this.menuId
        }
      },

      skip () {
        return !this.menuId
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
</style>
