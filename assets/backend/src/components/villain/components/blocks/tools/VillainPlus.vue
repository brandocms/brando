<template>
  <transition @appear="appear">
    <div
      v-show="state.showPlus"
      ref="plus"
      class="villain-editor-plus">
      <div
        key="plus"
        :class="active ? 'villain-editor-plus-active' : 'villain-editor-plus-inactive'">
        <a
          ref="plusLink"
          @click="clickPlus">
          <template v-if="draggingOver">
            {{ $t('move-block-here') }}
          </template>
          <template v-if="!draggingOver">
            <svg
              :class="active ? 'villain-svg-plus-open' : ''"
              class="villain-svg-plus"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 300 300">
              <circle
                cx="150"
                cy="150"
                r="142.7"
                stroke="#FFF"
                stroke-miterlimit="10" />
              <path
                fill="#FFF"
                d="M224.3 133.3v31.3H166v58.3h-31.3v-58.3H76.4v-31.3h58.3V75H166v58.3h58.3z" />
            </svg>
          </template>
        </a>

        <VueSlideUpDown
          :active="active"
          :duration="350">
          <div class="villain-editor-plus-block-name">
            {{ hoveredBlock }}
          </div>
          <div
            v-if="!vModuleMode"
            ref="blocks"
            class="villain-editor-plus-available-blocks">
            <div
              v-for="b in available.blocks"
              :key="b.name"
              class="villain-editor-plus-available-block"
              @mouseover="setHover(b.name)"
              @click="addBlock(b)">
              <div>
                <i
                  :class="b.icon"
                  class="fa fa-fw" />
              </div>
            </div>

            <div
              v-if="state.showModules"
              class="villain-editor-plus-available-block"
              @mouseover="setHover('moduler')"
              @click="revealModules">
              <div>
                <i class="fa fa-fw fa-window-restore" />
              </div>
            </div>
          </div>
        </VueSlideUpDown>
        <VueSlideUpDown
          :active="showingModules"
          :duration="350">
          <div
            v-if="namespacedModules"
            ref="modules"
            class="villain-editor-plus-available-modules">
            <div class="hardcoded-blocks">
              <div
                v-popover="$t('add-container')"
                class="datasource-block"
                @click="addContainer">
                <FontAwesomeIcon
                  icon="square"
                  size="lg" />
              </div>
              <div
                v-popover="$t('add-datasource')"
                class="datasource-block"
                @click="addDatasource">
                <FontAwesomeIcon
                  icon="database"
                  size="lg" />
              </div>
            </div>

            <div
              v-for="(tpls, key) in nonGeneralNamespacedModules"
              :key="key"
              class="villain-editor-plus-available-modules-group"
              @click="namespaceOpen === key ? namespaceOpen = null : namespaceOpen = key">
              <div
                class="villain-editor-plus-available-modules-namespace">
                <IconDropdown :open="namespaceOpen === key" /><strong>{{ key.toUpperCase() }}</strong>
              </div>
              <VueSlideUpDown
                :active="namespaceOpen === key"
                :duration="350">
                <div
                  v-for="(tp, idx) in tpls"
                  :key="'key-' + idx"
                  class="villain-editor-plus-available-module"
                  @click="addModule(tp)">
                  <div class="villain-editor-plus-available-modules-svg">
                    <div
                      v-if="tp.data.svg"
                      v-html="tp.data.svg" />
                  </div>
                  <div class="villain-editor-plus-available-modules-content left-margin">
                    <div class="villain-editor-plus-available-modules-title">
                      {{ tp.data.name }}
                    </div>
                    <div class="villain-editor-plus-available-modules-help">
                      {{ tp.data.help_text }}
                    </div>
                  </div>
                </div>
              </VueSlideUpDown>
            </div>

            <div
              v-for="(tp, idx) in namespacedModules.general"
              :key="'general-' + idx"
              class="villain-editor-plus-available-module"
              @click="addModule(tp)">
              <div
                class="villain-editor-plus-available-modules-svg"
                :class="tp.data.svg ? '' : 'empty'">
                <div
                  v-if="tp.data.svg"
                  v-html="tp.data.svg" />
              </div>
              <div class="villain-editor-plus-available-modules-content">
                <div class="villain-editor-plus-available-modules-title">
                  {{ tp.data.name }}
                </div>
                <div class="villain-editor-plus-available-modules-help">
                  {{ tp.data.help_text }}
                </div>
              </div>
            </div>
          </div>
          <div
            v-else
            class="mt-4">
            Ingen registrerte maler.
          </div>
        </VueSlideUpDown>
      </div>
    </div>
  </transition>
</template>

<script>

import VueSlideUpDown from 'vue-slide-up-down'
import { TweenMax } from 'gsap'
import IconDropdown from '../../icons/IconDropdown'

function createUID () {
  return (Date.now().toString(36) + Math.random().toString(36).substr(2, 5)).toUpperCase()
}

export default {
  name: 'VillainPlus',

  components: {
    VueSlideUpDown,
    IconDropdown
  },

  inject: [
    'available',
    'vModuleMode',
    'state'
  ],

  props: {
    parent: {
      type: String,
      default: null
    },

    after: {
      type: String,
      default: null
    }
  },

  data () {
    return {
      active: false,
      draggingOver: false,
      namespaceOpen: null,
      showingModules: false,
      hoveredBlock: 'Velg blokktype'
    }
  },

  computed: {
    namespacedModules () {
      if (!this.available.modules.length) {
        return null
      }
      return this.available.modules.reduce((objectsByKeyValue, obj) => {
        const value = obj.data.namespace
        objectsByKeyValue[value] = (objectsByKeyValue[value] || []).concat(obj)
        return objectsByKeyValue
      }, {})
    },

    nonGeneralNamespacedModules () {
      const { general, ...other } = this.namespacedModules
      return other
    }
  },

  mounted () {
    this.$refs.plusLink.addEventListener('dragenter', this.dragEnter)
    this.$refs.plusLink.addEventListener('dragover', this.dragOver)
    this.$refs.plusLink.addEventListener('dragleave', this.dragLeave)
    this.$refs.plusLink.addEventListener('drop', this.onDrop)
  },

  methods: {
    appear (el, done) {
      TweenMax.fromTo(el, 1.2, { x: -3, opacity: 0 }, { x: 0, opacity: 1, onComplete: done })
    },

    setHover (name) {
      this.hoveredBlock = name
    },

    revealModules () {
      this.showingModules = !this.showingModules
      if (this.showingModules) {
        setTimeout(() => {
          if (this.$refs.modules) {
            const elTop = this.$refs.modules.getBoundingClientRect().top
            const docBot = document.body.scrollTop + window.innerHeight
            const elHeight = this.$refs.modules.clientHeight
            const elBot = elTop + elHeight

            if (elBot > docBot) {
              const distance = elBot - docBot
              window.scrollBy({
                top: distance,
                behavior: 'smooth'
              })
            }
          }
        }, 250)
      }
    },

    clickPlus () {
      this.active = !this.active

      if (this.active && this.$refs.blocks) {
        setTimeout(() => {
          const elTop = this.$refs.blocks.getBoundingClientRect().top
          const docBot = document.body.scrollTop + window.innerHeight
          const elHeight = this.$refs.blocks.clientHeight
          const elBot = elTop + elHeight

          if (elBot > docBot) {
            const distance = elBot - docBot
            window.scrollBy({
              top: distance,
              behavior: 'smooth'
            })
          }
        }, 250)
      } else {
        this.showingModules = false
      }

      if (this.vModuleMode && this.active) {
        this.revealModules()
      }
    },

    addBlock (b) {
      const block = { ...b, uid: createUID() }
      this.active = false
      this.$emit('add', { block: block, after: this.after, parent: this.parent })
    },

    addDatasource () {
      const ds = this.available.blocks.find(b => b.component === 'Datasource')
      const block = { ...ds, uid: createUID() }
      this.active = false
      this.showingModules = false
      this.$emit('add', { block: block, after: this.after, parent: this.parent })
    },

    addContainer () {
      const ds = this.available.blocks.find(b => b.component === 'Container')
      const block = { ...ds, uid: createUID() }
      this.active = false
      this.showingModules = false
      this.$emit('add', { block: block, after: this.after, parent: this.parent })
    },

    addModule (tp) {
      const block = { ...tp, uid: createUID() }
      this.active = false
      this.showingModules = false
      this.$emit('add', { block: block, after: this.after, parent: this.parent })
    },

    onDrop (ev) {
      ev.preventDefault()

      const blockData = ev.dataTransfer.getData('application/villain')
      const block = JSON.parse(blockData)

      ev.currentTarget.classList.remove('villain-drag-over')
      this.draggingOver = false

      this.$emit('move', { block, after: this.after, parent: this.parent })
    },

    dragEnter (ev) {
      ev.preventDefault()
      ev.stopPropagation()
    },

    dragOver (ev) {
      ev.dataTransfer.dropEffect = 'copy'
      ev.currentTarget.classList.add('villain-drag-over')
      this.draggingOver = true
      ev.preventDefault()
      ev.stopPropagation()
    },

    dragLeave (ev) {
      ev.currentTarget.classList.remove('villain-drag-over')
      this.draggingOver = false
      ev.preventDefault()
      ev.stopPropagation()
    }
  }
}
</script>

<style lang="postcss" scoped>
.villain-editor-plus {
  margin-top: 1rem;
  color: theme(colors.villain.main);
  text-align: center;

  &.villain-drag-over {
    .villain-editor-plus-inactive {
      a {
        color: #fff;
        background-color: theme(colors.villain.main) !important;
        border: 0;
        text-decoration: none;

        &:hover {
          border: 0;
          text-decoration: none;
        }
      }
    }
  }

.hardcoded-blocks {
  display: flex;
  background-color: #fcfaf9;
  padding-top: 10px;
  padding-bottom: 8px;
}

.datasource-block {
  width: 50%;
  padding: 11px;
  cursor: pointer;
  &:hover {
    background-color: #efefef;
  }
}

.villain-editor-plus-available-modules {
  background-color: theme(colors.villain.blockBackground);
  padding: 1rem;
  max-width: 500px;
  margin: 0 auto;
  margin-top: 5px;
  font-size: 18px;

  .villain-editor-plus-available-modules-group {
    background-color: theme(colors.peach);
  }

  .villain-editor-plus-available-module {
    cursor: pointer;
    padding: 1rem 1rem 1rem 1rem;
    text-align: left;
    display: flex;
    align-items: center;

    &:hover {
      color: #fff;
      background-color: theme(colors.villain.main) !important;
    }

    .villain-editor-plus-available-module-svg {
      width: 120px;
      margin-right: 20px;
      background-color: theme(colors.peach);

      >>> svg {
        width: 100%;
        height: 100%;
        display: block;
      }
    }

    .villain-editor-plus-available-module-content {
      display: flex;
      flex-direction: column;
    }
  }

  .villain-editor-plus-available-modules-title {
    font-weight: 500;
    margin-bottom: 6px;
    font-size: 19px;
  }

  .villain-editor-plus-available-modules-svg {
    >>> svg {
      width: 150px;
      height: auto;
    }
  }

  .villain-editor-plus-available-modules-help {
    font-size: 14px;
  }

  .villain-editor-plus-available-modules-namespace {
    cursor: pointer;

    padding: 1rem;
    display: flex;
    align-items: center;

    &:hover {
      color: #fff;
      background-color: theme(colors.villain.main) !important;

      .svg-icon {
        fill: white;
      }
    }

    strong {
      font-size: 18px;
      font-weight: 400;
    }

    .svg-icon {
      width: 30px;
      height: 30px;
      float: left;
      margin-right: 30px;
    }
  }
}

  .villain-editor-plus-available-blocks {
    background-color: theme(colors.villain.blockBackground);
    position: relative;

    .villain-editor-plus-close {
      position: absolute;
      right: 5px;
      color: #fff;
      top: 5px;
    }

    .villain-editor-plus-available-block {
      color: theme(colors.dark);
      background-color: transparent;
      display: inline-block;
      padding: .5rem 1rem;
      margin: .25rem;
      cursor: pointer;
      transition: 500ms background-color ease, 500ms color ease;

      &:hover {
        background-color: theme(colors.blue);
        color: #fff;
        border: 0;
      }

      .villain-editor-plus-available-block-text {
        text-transform: uppercase;
        font-size: .7rem;
        font-weight: bold;
      }
    }
  }
}

.villain-svg-plus {
  width: 30px;
  transition: transform 1s ease;
  transform: rotateZ(0deg);

  circle {
    transition: fill 750ms ease;
    fill: theme(colors.villain.plus);
  }

  path {
    transition: fill 350ms ease;
    fill: #fff;
  }

  &.villain-svg-plus-open {
    transform: rotateZ(135deg);

    circle {
      transition: fill 750ms ease;
      fill: transparent;
    }

    path {
      transition: fill 350ms ease;
      fill: theme(colors.villain.main);
    }
  }
}

.villain-editor-plus-inactive {
  * {
    pointer-events: none;
  }

  a {
    pointer-events: auto;
    * {
      pointer-events: none;
    }
  }
}

.villain-editor-plus-inactive, .villain-editor-plus-active {
  a {
    display: inline-block;
    font-size: 2.5rem;
    line-height: 2.5rem;
    font-weight: bold;
    cursor: pointer;
    color: theme(colors.villain.main);
    background-color: transparent;
    transition: all 250ms ease;
    border: 0;
    text-decoration: none;

    &:hover {
      background-color: transparent;
      border: 0;
      text-decoration: none;
    }
  }
}

.villain-editor-plus-available-modules-content {
  text-align: left;

  &.left-margin {
    margin-left: 30px;
  }
}

.villain-editor-plus-block-name {
  text-transform: uppercase;
  font-size: .65rem;
  margin-bottom: 10px;
  font-weight: bold;
  display: inline-block;
  background: theme(colors.villain.blockBackground);
  padding: 3px 7px;
}

.villain-editor-plus-inactive {
  a {
    &:hover {
      background-color: transparent;
      .villain-svg-plus {
        circle {
          transition: fill 350ms ease;
          fill: theme(colors.villain.main);
        }
      }
    }
  }
}
</style>

<i18n>
  {
    "en": {
      "move-block-here": "Move block here",
      "add-datasource": "+ Datasource (advanced)",
      "add-container": "+ Container"
    },
    "no": {
      "move-block-here": "Flytt blokken hit",
      "add-datasource": "+ Datakilde (avansert)",
      "add-container": "+ Seksjon"
    }
  }
</i18n>
