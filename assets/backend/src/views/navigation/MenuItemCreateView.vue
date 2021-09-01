<template>
  <article>
    <ContentHeader>
      <template #title>
        Nytt menypunkt
      </template>
    </ContentHeader>
    <MenuItemForm
      :menu-item="menuItem"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import MenuItemForm from './MenuItemForm'

export default {
  components: {
    MenuItemForm
  },

  props: {
    menuId: {
      type: [String, Number],
      required: true
    }
  },

  data () {
    return {
      menuItem: {}
    }
  },

  methods: {
    async save () {
      const menuItemParams = this.$utils.stripParams({
        ...this.menuItem, menuId: this.menuId
      }, ['__typename', 'id'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateMenuItem($menuItemParams: MenuItemParams) {
              createMenuItem(
                menuItemParams: $menuItemParams
              ) {
                id
              }
            }
          `,
          variables: {
            menuItemParams
          }
        })

        this.$toast.success({ message: 'Menypunkt opprettet' })
        this.$router.push({ name: 'navigation' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>
