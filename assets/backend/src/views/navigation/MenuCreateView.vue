<template>
  <article>
    <ContentHeader>
      <template #title>
        Ny meny
      </template>
    </ContentHeader>
    <MenuForm
      :menu="menu"
      :save="save" />
  </article>
</template>

<script>

import gql from 'graphql-tag'
import MenuForm from './MenuForm'

export default {
  components: {
    MenuForm
  },

  data () {
    return {
      menu: {}
    }
  },

  methods: {
    async save () {
      const menuParams = this.$utils.stripParams(this.menu, ['__typename', 'id'])

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation CreateMenu($menuParams: MenuParams) {
              createMenu(
                menuParams: $menuParams
              ) {
                id
              }
            }
          `,
          variables: {
            menuParams
          }
        })

        this.$toast.success({ message: 'Meny opprettet' })
        this.$router.push({ name: 'navigation' })
      } catch (err) {
        this.$utils.showError(err)
      }
    }
  }
}
</script>

<style lang="postcss" scoped>

</style>
