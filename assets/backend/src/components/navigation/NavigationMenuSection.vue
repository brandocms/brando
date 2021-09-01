<template>
  <section>
    <header>
      <h3>{{ section.name }}</h3>
      <div class="line"></div>
    </header>
    <NavigationMenuSectionItem
      v-for="item in section.items"
      :key="item.name"
      :item="item"
      @hover="$emit('hover', $event.target)" />
  </section>
</template>

<script>
import NavigationMenuSectionItem from './NavigationMenuSectionItem'

export default {
  components: {
    NavigationMenuSectionItem
  },

  props: {
    section: {
      type: Object,
      required: true
    }
  }
}
</script>

<style lang="postcss" scoped>
  section {
    @space margin-top sm;

    header {
      display: flex;
      margin-bottom: 10px;
      position: relative;

      h3 {
        @fontsize nav.section;
        font-style: normal;
        font-weight: normal;
        color: rgba(0, 0, 0, 0.7);
        text-transform: uppercase;
      }

      .line {
        background-color: theme(colors.dark);
        height: 1px;
        width: 100%;
        left: 0;
        transform: translateY(10px);
        margin-left: 10px;
      }
    }
  }
</style>
