<template>
  <transition
    name="fade"
    appear>
    <header id="content-header">
      <div class="content">
        <section class="main">
          <h1>
            <slot name="title">
            </slot>
          </h1>
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

export default {}

</script>

<style lang="postcss" scoped>
  #content-header {
    @space margin-top sm;
    @space padding-bottom xs;
    @space margin-bottom sm;
    flex-direction: column;
    border-bottom: 1px solid theme(colors.dark);

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
