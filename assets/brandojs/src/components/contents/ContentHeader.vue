<template>
  <transition
    name="fade"
    appear>
    <header id="content-header">
      <button
        class="toggle-menu"
        @click="toggleFullscreen">
        <template v-if="fullscreen">
          &rarr;
        </template>
        <template v-else>
          &larr;
        </template>
      </button>

      <div class="content">
        <section class="main">
          <h2>
            <slot name="title">
            </slot>
          </h2>
          <h3>
            <slot name="subtitle">
            </slot>
          </h3>
        </section>
        <section class="help">
          <slot name="help">
          </slot>
        </section>
      </div>
    </header>
  </transition>
</template>

<script>

import gql from 'graphql-tag'

export default {
  methods: {
    toggleFullscreen () {
      this.$apollo.mutate({
        mutation: gql`
          mutation setFullscreen ($value: String!) {
            fullscreenSet (value: $value) @client
          }
        `,
        variables: {
          value: !this.fullscreen
        }
      })
    }
  },

  apollo: {
    fullscreen: gql`
      query getFullscreen {
        fullscreen @client
      }
    `
  }
}

</script>

<style lang="postcss" scoped>
  #content-header {
    @space padding-bottom md;
    @space margin-bottom md;
    flex-direction: column;
    border-bottom: 1px solid theme(colors.dark);

    .toggle-menu {
      @space margin-top sm;
      @space margin-bottom md;

      border: 1px solid theme(colors.dark);
      width: 50px;
      height: 50px;
      padding-top: 8px;

      &:hover {
        background-color: theme(colors.dark);
        color: theme(colors.peach);
      }
    }

    .content {
      @row;
      align-items: flex-end;

      .main {
        @column 8/16;
      }

      .help {
        @column 8/16;
        @fontsize lg;
        font-weight: 200;
      }
    }
  }
</style>
