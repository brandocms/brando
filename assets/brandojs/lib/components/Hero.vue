<template>
  <div class="container">
    <div class="card">
      <div class="card-body">
        <div class="jumbotron mb-0 text-center">
          <h1 class="display-1 text-uppercase text-strong">
            <slot name="heading"></slot>
          </h1>
          <p class="lead">
            <slot name="lead"></slot>
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'Hero'
}
</script>
