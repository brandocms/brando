<template>
  <div class="villain-module-important-variables">
    <div
      v-for="(v, key) in value"
      :key="key">
      <div
        v-if="value[key].important"
        class="field-wrapper">
        <template v-if="value[key].type === 'text'">
          <KInput
            v-model="value[key].value"
            :name="`vars[${key}]`"
            :label="v.label" />
        </template>
        <template v-if="value[key].type === 'string'">
          <KInput
            v-model="value[key].value"
            :name="`vars[${key}]`"
            :label="v.label" />
        </template>
        <template v-else-if="value[key].type === 'boolean'">
          <KInputToggle
            v-model="value[key].value"
            :name="`vars[${key}]`"
            :label="v.label" />
        </template>
        <template v-else-if="value[key].type === 'table'">
          TABLE!
        </template>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  props: {
    value: {
      type: Object,
      default: () => {}
    }
  }
}
</script>

<style>

</style>
