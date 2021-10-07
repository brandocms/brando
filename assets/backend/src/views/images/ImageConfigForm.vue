<template>
  <div>
    <h2>
      Hovedkonfigurasjon
    </h2>
    <KInput
      v-model="config.upload_path"
      rules="required"
      name="config[upload_path]"
      label="Opplastingsbane"
      placeholder="Opplastingsbane" />
    <KInput
      v-model="config.size_limit"
      rules="required"
      name="config[size_limit]"
      label="Størrelsesbegrensing (i bytes)"
      placeholder="Størrelsesbegrensing (i bytes)" />
    <KInputCheckbox
      v-model="config.random_filename"
      name="config[random_filename]"
      label="Vilkårlig filnavn" />

    <h2>
      Størrelsesnøkler
    </h2>

    <button
      class="btn btn-primary"
      @click.prevent="addKey">
      Ny nøkkel
    </button>
    <button
      class="btn btn-primary"
      @click.prevent="addMultiGeoKey">
      Ny liggende/stående nøkkel
    </button>

    <div
      v-for="(size, key) in config.sizes"
      :key="key">
      <hr>
      <div class="form-group">
        <div class="label-wrapper">
          <label
            for="size_size_"
            class="control-label">
            Nøkkelnavn
          </label>
        </div>
        <input
          :value="key"
          class="form-control"
          type="text"
          @change="changeKey($event, key)">
      </div>
      <template v-if="isMultiGeo(size)">
        <div class="row">
          <div class="col">
            <KInput
              v-model="size.portrait.size"
              rules="required"
              name="size[portrait][size]"
              label="Stående størrelsesgeometri (WxH)"
              placeholder="WxH" />
          </div>
          <div class="col">
            <KInput
              v-model="size.portrait.quality"
              rules="required"
              name="size[portrait][quality]"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.portrait.crop"
              name="size[portrait][crop]"
              label="Bildebeskjæring" />
          </div>
        </div>
        <div class="row">
          <div class="col">
            <KInput
              v-model="size.landscape.size"
              rules="required"
              name="size[landscape][size]"
              label="Liggende størrelsesgeometri (WxH)"
              placeholder="WxH" />
          </div>
          <div class="col">
            <KInput
              v-model="size.landscape.quality"
              rules="required"
              name="size[landscape][quality]"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.landscape.crop"
              name="size[landscape][crop]"
              label="Bildebeskjæring" />
          </div>
        </div>
      </template>
      <template v-else>
        <div class="row">
          <div class="col">
            <KInput
              v-model="size.size"
              rules="required"
              :name="`size[size][${key}]`"
              label="Størrelsesgeometri (WxH)"
              placeholder="Beskrivelse" />
          </div>
          <div class="col">
            <KInput
              v-model="size.quality"
              rules="required"
              :name="`size[quality][${key}]`"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.crop"
              :name="`size[crop][${key}]`"
              label="Bildebeskjæring" />
          </div>
        </div>
        <button
          class="btn btn-outline-secondary"
          @click.prevent="delKey(key)">
          Slett nøkkel
        </button>
      </template>
    </div>
  </div>
</template>

<script>

export default {
  props: {
    config: {
      type: Object,
      required: true
    }
  },

  methods: {
    addKey () {
      this.$set(this.config.sizes, 'navn', {
        size: 'WxH',
        crop: false,
        quality: '80'
      })
    },

    addMultiGeoKey () {
      this.$set(this.config.sizes, 'navn', {
        portrait: {
          size: 'WxH',
          crop: false,
          quality: '80'
        },
        landscape: {
          size: 'WxH',
          crop: false,
          quality: '80'
        }
      })
    },

    isMultiGeo (size) {
      if ('portrait' in size) {
        return true
      }
      return false
    },

    delKey (key) {
      this.$delete(this.config.sizes, key)
    },

    changeKey (ev, key) {
      this.config.sizes = Object.assign(
        {},
        ...Object.keys(this.config.sizes)
          .map(k => {
            if (k === key) {
              return ({ [ev.target.value]: this.config.sizes[k] })
            }
            return ({ [k]: this.config.sizes[k] })
          })
      )
    }
  }
}
</script>

<style lang="postcss" scoped>
  h2 {
    @space margin-bottom sm;
  }

  .btn {
    width: 300px !important;

    + .btn {
      margin-top: -1px;
    }
  }

  .btn-outline-secondary {
    width: 200px !important;
  }

  input.form-control {
    @fontsize lg;
    padding-top: 12px;
    padding-bottom: 12px;
    padding-left: 15px;
    padding-right: 15px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;
    margin-bottom: 15px;

    &.monospace {
      @fontsize base(0.8);
      font-family: theme(typography.families.mono);
      padding-bottom: 12px;
      padding-top: 16px;
    }
  }

  label.control-label {
    font-weight: 500;
  }
</style>
