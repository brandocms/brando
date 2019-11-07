<template>
  <div>
    <h5 class="pull-out">
      Hovedkonfigurasjon
    </h5>
    <KInput
      v-model="config.upload_path"
      rules="required"
      :value="config.upload_path"
      name="config[upload_path]"
      label="Opplastingsbane"
      placeholder="Opplastingsbane"
      data-vv-name="config[upload_path]"
      data-vv-value-path="innerValue" />
    <KInput
      v-model="config.size_limit"
      rules="required"
      :value="config.size_limit"
      name="config[size_limit]"
      label="Størrelsesbegrensing (i bytes)"
      placeholder="Størrelsesbegrensing (i bytes)"
      data-vv-name="config[size_limit]"
      data-vv-value-path="innerValue" />
    <KInputCheckbox
      v-model="config.random_filename"
      :value="config.random_filename"
      name="config[random_filename]"
      label="Vilkårlig filnavn"
      data-vv-name="config[random_filename]"
      data-vv-value-path="innerValue" />

    <h5 class="pull-out">
      Størrelsesnøkler
    </h5>

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
              :value="size.portrait.size"
              name="size[portrait][size]"
              label="Stående størrelsesgeometri (WxH)"
              placeholder="WxH"
              data-vv-name="size[portrait][size]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInput
              v-model="size.portrait.quality"
              rules="required"
              :value="size.portrait.quality"
              name="size[portrait][quality]"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)"
              data-vv-name="size[portrait][quality]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.portrait.crop"
              :value="size.portrait.crop"
              name="size[portrait][crop]"
              label="Bildebeskjæring"
              data-vv-name="size[portrait][crop]"
              data-vv-value-path="innerValue" />
          </div>
        </div>
        <div class="row">
          <div class="col">
            <KInput
              v-model="size.landscape.size"
              rules="required"
              :value="size.landscape.size"
              name="size[landscape][size]"
              label="Liggende størrelsesgeometri (WxH)"
              placeholder="WxH"
              data-vv-name="size[landscape][size]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInput
              v-model="size.landscape.quality"
              rules="required"
              :value="size.landscape.quality"
              name="size[landscape][quality]"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)"
              data-vv-name="size[landscape][quality]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.landscape.crop"
              :value="size.landscape.crop"
              name="size[landscape][crop]"
              label="Bildebeskjæring"
              data-vv-name="size[landscape][crop]"
              data-vv-value-path="innerValue" />
          </div>
        </div>
      </template>
      <template v-else>
        <div class="row">
          <div class="col">
            <KInput
              v-model="size.size"
              rules="required"
              :value="size.size"
              name="size[size]"
              label="Størrelsesgeometri (WxH)"
              placeholder="Beskrivelse"
              data-vv-name="size[size]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInput
              v-model="size.quality"
              rules="required"
              :value="size.quality"
              name="size[quality]"
              label="Kvalitetsprosent (0-100)"
              placeholder="Kvalitetsprosent (0-100)"
              data-vv-name="size[quality]"
              data-vv-value-path="innerValue" />
          </div>
          <div class="col">
            <KInputCheckbox
              v-model="size.crop"
              :value="size.crop"
              name="size[crop]"
              label="Bildebeskjæring"
              data-vv-name="size[crop]"
              data-vv-value-path="innerValue" />
          </div>
        </div>
        <button
          class="btn btn-outline-secondary"
          @click.prevent="delKey(key)">
          Slett nøkkel
        </button>
      </template>
    </div>
    <hr>
    <button
      class="btn btn-secondary"
      @click.prevent="save">
      Lagre konfigurasjon
    </button>
  </div>
</template>

<script>

/*
{"xlarge", "2400w"},
{"large", "1164w"},
{"medium", "936w"},
{"small", "582w"}
*/

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

    save () {
      this.$emit('save', this.config)
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
