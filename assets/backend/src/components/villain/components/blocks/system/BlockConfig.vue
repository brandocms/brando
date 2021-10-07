<template>
  <KModal
    v-if="modalVisible"
    ref="modal"
    v-shortkey="['esc']"
    :ok-text="$t('closeConfig')"
    @shortkey.native="closeConfig"
    @ok="closeConfig">
    <template #header>
      <h5>{{ $t('config') }}</h5>
    </template>
    <div
      ref="config"
      class="villain-block-config">
      <div class="villain-block-config-content">
        <slot :cfg="innerValue" />
      </div>
    </div>
  </KModal>
</template>

<script>
export default {
  props: {
    value: {
      type: Object,
      default: () => {}
    }
  },

  data () {
    return {
      modalVisible: false,
      innerValue: {}
    }
  },

  created () {
    this.innerValue = this.value
  },

  methods: {
    openConfig () {
      this.modalVisible = true
    },

    async closeConfig () {
      await this.$refs.modal.close()
      this.modalVisible = false
      this.$emit('close', this.innerValue)
      this.$emit('input', this.innerValue)
    }
  }
}
</script>
<i18n>
{
  "en": {
    "config": "Configure block",
    "closeConfig": "Close config"
  },
  "no": {
    "config": "Konfigurer blokk",
    "closeConfig": "Lukk konfigurasjon"
  }
}
</i18n>
