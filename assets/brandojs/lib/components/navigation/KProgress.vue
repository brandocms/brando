<template>
  <div
    class="alert-backdrop">
    <div
      class="kprogress">
      <div
        v-if="percent"
        class="kprogress-percent">
        {{ percent }}%
      </div>
      <div class="kprogress-content">
        <transition-group
          name="slide-fade"
          appear>
          <div
            v-for="k in Object.keys(status)"
            :key="k">
            <transition
              name="fade"
              mode="out-in"
              :duration="250">
              <i
                v-if="status[k].percent !== 100"
                key="working"
                :class="'fal fa-fw mr-3 fa-cog fa-spin'" />
              <i
                v-else
                key="done"
                :class="'fal fa-fw mr-3 fa-check text-success'" />
            </transition>
            <div
              class="d-inline-block"
              v-html="status[k].content" />
          </div>
        </transition-group>
      </div>
    </div>
  </div>
</template>
<script>
export default {
  props: {
    status: {
      type: Object,
      default: () => {}
    },

    percent: {
      type: Number,
      default: null
    }
  }
}
</script>
