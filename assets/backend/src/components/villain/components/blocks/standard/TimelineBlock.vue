<template>
  <div>
    <Block
      :block="block"
      :parent="parent"
      @add="$emit('add', $event)"
      @move="$emit('move', $event)"
      @duplicate="$emit('duplicate', $event)"
      @hide="$emit('hide', $event)"
      @show="$emit('show', $event)"
      @delete="$emit('delete', $event)">
      <ul class="villain-timeline">
        <li
          v-for="(item, idx) in block.data.rows"
          :key="idx"
          class="villain-timeline-item">
          <p class="villain-timeline-item-date">
            {{ item.caption }}
          </p>
          <div class="villain-timeline-item-content">
            <div class="villain-timeline-item-content-inner">
              {{ item.text }}
            </div>
          </div>
        </li>
      </ul>
      <div class="helpful-actions">
        <ButtonTiny
          @click="$refs.config.openConfig()">
          Konfigurér blokk
        </ButtonTiny>
      </div>
    </Block>
    <BlockConfig
      ref="config"
      v-model="block.data">
      <template #default="{ cfg }">
        <div
          v-for="(item, idx) in cfg.rows"
          :key="idx + 'cfg'"
          class="form-group">
          <KInput
            v-model="item.caption"
            label="Datapunkt"
            :name="`data[caption][${idx}]`" />

          <KInputTextarea
            v-model="item.text"
            :rows="2"
            label="Innhold"
            :name="`data[text][${idx}]`" />

          <ButtonSecondary
            @click="deleteItem(cfg, item)">
            Slett punkt
          </ButtonSecondary>

          <hr />
        </div>
        <ButtonSecondary
          @click="addItem(cfg)">
          Nytt punkt
        </ButtonSecondary>
      </template>
    </BlockConfig>
  </div>
</template>

<script>
import Block from '../system/Block'

export default {
  name: 'TimelineBlock',

  components: {
    Block
  },

  props: {
    block: {
      type: Object,
      default: () => {}
    },

    parent: {
      type: String,
      default: null
    }
  },

  data () {
    return {
      customClass: '',
      uid: null
    }
  },

  updated () {
    console.debug('<TimelineBlock /> updated')
  },

  methods: {
    addItem (cfg) {
      cfg.rows.push({
        caption: '2022',
        text: 'Innhold'
      })
    },

    deleteItem (cfg, item) {
      const i = cfg.rows.find(b => b === item)
      const idx = cfg.rows.indexOf(i)

      cfg.rows = [
        ...cfg.rows.slice(0, idx),
        ...cfg.rows.slice(idx + 1)
      ]
    }
  }
}
</script>

<style lang="postcss" scoped>
  .villain-timeline {
    list-style: none;
  }
  .villain-timeline > li {
    margin-bottom: 60px;
  }

  /* for Desktop */
  @media ( min-width : 640px ){
    .villain-timeline > li {
      overflow: hidden;
      margin: 0;
      position: relative;
    }
    .villain-timeline-item-date {
      width: 110px;
      float: left;
      margin-top: 21px;
      font-size: 85%;
      font-weight: 500;
    }
    .villain-timeline-item-content {
      width: 75%;
      float: left;
      border-left: 3px #e5e5d1 solid;
      padding-left: 30px;
      min-height: 60px;
      display: flex;
      align-items: center;
    }
    .villain-timeline-item-content:before {
      content: '';
      width: 12px;
      height: 12px;
      background: theme(colors.villain.main);
      position: absolute;
      left: 106px;
      top: 24px;
      border-radius: 100%;
    }

    .villain-timeline-item-content-inner {
      font-size: 95%;
    }
  }
</style>
