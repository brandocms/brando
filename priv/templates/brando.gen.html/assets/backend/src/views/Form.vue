<template>
  <div class="form-wrapper">
    <ValidationObserver
      ref="observer"
      v-slot="{ invalid }">
      <!--
      FORM FIELDS HERE
      --><%= for {_v, k} <- vue_inputs do %>
      <%= List.first(k) %><% {_, r} = List.pop_at(k, 0); {_, remainder} = List.pop_at(r, -1) %><%= for prop <- remainder do %>
        <%= prop %><% end %>
      />
      <% end %>
      <button
        :disabled="!!loading"
        class="btn btn-secondary"
        @click="validate">
        Lagre
      </button>

      <router-link
        :disabled="!!loading"
        :to="{ name: '<%= plural %>' }"
        class="btn btn-outline-secondary">
        Tilbake til oversikten
      </router-link>
    </ValidationObserver>
  </div>
</template>

<script>
export default {
  props: {
    <%= vue_singular %>: {
      type: Object,
      required: true
    },
    loading: {
      type: Number,
      required: true
    }
  },

  methods: {
    async validate () {
      const isValid = await this.$refs.observer.validate()
      if (!isValid) {
        alertError('Feil i skjema', 'Vennligst se over og rett feil i rødt')
        this.loading = 0
        return
      }
      this.$emit('save')
    }
  }
}
</script>
