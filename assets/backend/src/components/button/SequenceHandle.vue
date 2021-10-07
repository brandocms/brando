<template>
  <div class="center">
    <svg
      width="15"
      height="15"
      viewBox="0 0 15 15"
      fill="none"
      xmlns="http://www.w3.org/2000/svg">
      <circle
        cx="1.5"
        cy="1.5"
        r="1.5" />
      <circle
        cx="7.5"
        cy="1.5"
        r="1.5" />
      <circle
        cx="13.5"
        cy="1.5"
        r="1.5" />
      <circle
        cx="1.5"
        cy="7.5"
        r="1.5" />
      <circle
        cx="7.5"
        cy="7.5"
        r="1.5" />
      <circle
        cx="13.5"
        cy="7.5"
        r="1.5" />
      <circle
        cx="1.5"
        cy="13.5"
        r="1.5" />
      <circle
        cx="7.5"
        cy="13.5"
        r="1.5" />
      <circle
        cx="13.5"
        cy="13.5"
        r="1.5" />
    </svg>
  </div>
</template>

<script>
export default {

}
</script>

<style lang="postcss" scoped>
  div {
    width: 15px;
    cursor: move;

    &.center {
      margin: 0 auto;
    }

    svg {
      circle {
        fill: theme(colors.dark);
      }

      &:hover {
        circle {
          fill: theme(colors.blue);
        }
      }
    }
  }

</style>
