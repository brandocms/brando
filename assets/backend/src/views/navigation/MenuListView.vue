<template>
  <article>
    <ContentHeader>
      <template #title>
        {{ $t('menus.title') }}
      </template>
      <template #subtitle>
        {{ $t('menus.subtitle') }}
      </template>
      <template #help>
        <div>
          <Dropdown>
            <template #default>
              {{ $t('menus.actions') }}
            </template>
            <template #content>
              <li>
                <router-link :to="{ name: 'navigation-new' }">
                  {{ $t('menus.new') }}
                </router-link>
              </li>
            </template>
          </Dropdown>
        </div>
      </template>
    </ContentHeader>

    <div class="row">
      <div class="half">
        <h2>{{ $t('menus.index') }}</h2>
      </div>
    </div>
    <ContentList
      v-if="menus"
      :entries="menus"
      :sortable="true"
      :status="true"
      :filter-keys="['title']"
      child-property="items"
      @updateQuery="queryVars = $event"
      @sort="sortMenus">
      <template #empty>
        Ingen menyer fantes. Det kan være menyene er hardkodet i applikasjonen!
      </template>
      <template #selected="{ entries, clearSelection}">
        <li>
          <button
            @click="deleteEntries(entries, clearSelection)">
            Slett menyer
          </button>
        </li>
      </template>
      <template #row="{ entry }">
        <div class="col-1">
          <div class="circle">
            <span>{{ entry.language }}</span>
          </div>
        </div>
        <div class="col-7 title">
          <router-link
            :to="{ name: 'navigation-edit', params: { menuId: entry.id } }"
            class="link name-link">
            {{ entry.title }}
          </router-link><br>
          <div class="badge">
            {{ entry.key }}
          </div>
        </div>
        <div class="col-2 justify-end">
          <div class="badge">
            <FontAwesomeIcon
              icon="map"
              size="sm" />
            {{ $t('menus.menu') }}
          </div>
        </div>
        <div class="col-4">
          <ItemMeta
            :entry="entry"
            :user="entry.creator" />
        </div>
        <div class="col-1">
          <CircleDropdown>
            <li>
              <button @click="createSubItem(entry.id)">
                {{ $t('menus.new-item') }}
              </button>
            </li>
            <li>
              <router-link
                :to="{ name: 'navigation-edit', params: { menuId: entry.id } }">
                {{ $t('menus.edit-menu') }}
              </router-link>
            </li>

            <li>
              <button
                type="button"
                @click="duplicateMenu(entry)">
                {{ $t('menus.duplicate-menu') }}
              </button>
            </li>

            <li>
              <button
                type="button"
                @click="deleteEntry(entry.id)">
                {{ $t('menus.delete-menu') }}
              </button>
            </li>
          </CircleDropdown>
          <KModal
            v-if="showEditMenuModal === entry.id"
            ref="editModal"
            v-shortkey="['esc', 'enter']"
            @shortkey.native="showEditMenuModal = 0">
            <MenuItemForm
              :menu-item="entry"
              :save="save" />
          </KModal>
        </div>
      </template>
      <template #children="{ children, entry: rootMenu }">
        <ContentList
          v-if="children.length"
          :level="2"
          :entries="children"
          :sortable="true"
          :status="true"
          :sort-parent="rootMenu.id"
          :sortable-integer-ids="false"
          child-property="items"
          sequence-handle="item-sequence-handle"
          @sort="sortItems($event, rootMenu, rootMenu)">
          <template #row="{ entry: item }">
            <div class="col-1"></div>
            <div class="col-6 subtitle">
              <div class="arrow">
                ↳
              </div>
              <div class="flex-v">
                <div
                  class="clickable"
                  @click="showEditMenuItemModal = item.id">
                  {{ item.title || 'Ingen tittel' }}
                </div>
                <div class="keys">
                  <div class="badge url">
                    <FontAwesomeIcon
                      icon="globe-americas"
                      size="sm" /> &rarr; {{ item.url }}
                  </div>
                </div>
              </div>
            </div>
            <div class="col-3 justify-end">
              <div class="badge url">
                <FontAwesomeIcon
                  icon="map-pin"
                  size="sm" /> {{ $t('menus.item') }}
              </div>
            </div>
            <div class="col-4 justify-end">
            </div>
            <div class="col-1">
              <CircleDropdown>
                <li>
                  <button @click="showEditMenuItemModal = item.id">
                    {{ $t('menus.edit-item') }}
                  </button>
                </li>

                <li>
                  <button @click="createSubItem(rootMenu.id, item.id)">
                    {{ $t('menus.new-subitem') }}
                  </button>
                </li>

                <li>
                  <button @click="deleteItem(rootMenu, item)">
                    {{ $t('menus.delete-item') }}
                  </button>
                </li>
              </CircleDropdown>
              <KModal
                v-if="showEditMenuItemModal === item.id"
                ref="editModal"
                v-shortkey="['esc', 'enter']"
                @ok="saveItem(rootMenu.id)"
                @shortkey.native="showEditMenuItemModal = 0">
                <KInputStatus
                  v-model="item.status"
                  name="item[status]"
                  rules="required"
                  label="Status" />

                <KInputToggle
                  v-model="item.openInNewWindow"
                  name="item[openInNewWindow]"
                  label="Åpne i nytt vindu" />

                <KInput
                  v-model="item.title"
                  label="Tittel"
                  rules="required"
                  placeholder="Tittel"
                  name="item[title]" />

                <KInput
                  v-model="item.key"
                  rules="required"
                  name="item[key]"
                  type="text"
                  label="Nøkkel"
                  placeholder="Nøkkel" />

                <KInput
                  v-model="item.url"
                  rules="required"
                  name="item[key]"
                  label="URL"
                  placeholder="/side" />
              </KModal>
            </div>
          </template>
          <template #children="{ children: subChildren, entry }">
            <ContentList
              v-if="subChildren.length"
              :level="3"
              :entries="subChildren"
              :sortable="true"
              :status="true"
              :sort-parent="rootMenu.id"
              :sortable-integer-ids="false"
              sequence-handle="item-sequence-handle"
              @sort="sortItems($event, entry, rootMenu)">
              <template #row="{ entry: item }">
                <div class="col-1">
                </div>
                <div class="col-1">
                  <div class="circle"></div>
                </div>
                <div class="col-5 subtitle">
                  <div class="arrow">
                    ↳
                  </div>
                  <div class="flex-v">
                    <div
                      class="clickable"
                      @click="showEditMenuItemModal = item.id">
                      {{ item.title || 'Ingen tittel' }}
                    </div>
                    <div class="keys">
                      <div class="badge">
                        {{ item.key }}
                      </div>
                    </div>
                  </div>
                </div>
                <div class="col-3 justify-end">
                  <div class="badge">
                    {{ $t('menus.item') }}
                  </div>
                </div>
                <div class="col-4 justify-end">
                </div>
                <div class="col-1">
                  <CircleDropdown>
                    <li>
                      <button @click="showEditMenuItemModal = item.id">
                        {{ $t('menus.edit-item') }}
                      </button>
                    </li>

                    <li>
                      <button @click="deleteItem(rootMenu, item)">
                        {{ $t('menus.delete-item') }}
                      </button>
                    </li>
                  </CircleDropdown>
                  <KModal
                    v-if="showEditMenuItemModal === item.id"
                    ref="editModal"
                    v-shortkey="['esc', 'enter']"
                    @ok="saveItem(rootMenu.id)"
                    @shortkey.native="showEditMenuItemModal = 0">
                    <KInputStatus
                      v-model="item.status"
                      name="item[status]"
                      rules="required"
                      label="Status" />

                    <KInputToggle
                      v-model="item.openInNewWindow"
                      name="item[openInNewWindow]"
                      label="Åpne i nytt vindu" />

                    <KInput
                      v-model="item.title"
                      label="Tittel"
                      rules="required"
                      placeholder="Tittel"
                      name="item[title]" />

                    <KInput
                      v-model="item.key"
                      rules="required"
                      name="item[key]"
                      type="text"
                      label="Nøkkel"
                      placeholder="Nøkkel" />

                    <KInput
                      v-model="item.url"
                      rules="required"
                      name="item[key]"
                      label="URL"
                      placeholder="/side" />
                  </KModal>
                </div>
              </template>
            </ContentList>
          </template>
        </ContentList>
      </template>
    </ContentList>
  </article>
</template>

<script>
import gql from 'graphql-tag'
import GET_MENUS from '../../gql/navigation/MENUS_QUERY.graphql'
import locale from '../../locales/menus'
import MenuItemForm from './MenuItemForm'

export default {
  components: {
    MenuItemForm
  },

  inject: ['adminChannel'],

  data () {
    return {
      showEditMenuModal: 0,
      showEditMenuItemModal: 0,
      visibleChildren: [],
      queryVars: {
        filter: null,
        offset: 0,
        limit: 50,
        status: 'all'
      }
    }
  },

  methods: {
    sortMenus (seq) {
      this.adminChannel.channel
        .push('menus:sequence_menus', { ids: seq })
        .receive('ok', payload => {
          this.$toast.success({ message: this.$t('menus.sequence-updated') })
        })
    },

    sortItems (seq, menu, rootMenu) {
      const sortedArray = menu.items.sort((a, b) => {
        return seq.indexOf(a.id) - seq.indexOf(b.id)
      })

      this.$set(menu, 'items', sortedArray)

      this.saveMenu(rootMenu)
    },

    stripItems (items) {
      return items.map(i => {
        delete i.__typename
        if (i.items.length) {
          i.items = this.stripItems(i.items)
        }
        return i
      })
    },

    createSubItem (menuId, itemId) {
      const menu = this.menus.find(m => parseInt(m.id) === parseInt(menuId))
      const newItems = [{
        id: this.$utils.guid(),
        key: 'key',
        status: 'published',
        openInNewWindow: false,
        title: 'Tittel',
        items: [],
        url: '/url'
      }]
      if (itemId) {
        const item = this.findItem(menu.items, itemId)
        this.$set(item, 'items', [...item.items, ...newItems])
      } else {
        this.$set(menu, 'items', [...menu.items, ...newItems])
      }
    },

    findItem (items, itemId) {
      for (let i = 0; i < items.length; i += 1) {
        if (items[i].id === itemId) {
          return items[i]
        }

        if (items[i].items.length) {
          this.findItem(items[i].items, itemId)
        }
      }
      return null
    },

    saveItem (menuId) {
      this.showEditMenuItemModal = 0
      const menu = this.menus.find(m => parseInt(m.id) === parseInt(menuId))

      this.saveMenu(menu)
    },

    async saveMenu (menu) {
      let menuParams = this.$utils.stripParams(
        menu, [
          '__typename',
          'id',
          'insertedAt',
          'updatedAt',
          'creator'
        ])

      // strip items
      menuParams = { ...menuParams, items: this.stripItems(menuParams.items) }

      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateMenu($menuId: ID!, $menuParams: MenuParams) {
              updateMenu(
                menuId: $menuId,
                menuParams: $menuParams
              ) {
                id
              }
            }
          `,
          variables: {
            menuParams,
            menuId: menu.id
          }
        })

        this.$toast.success({ message: 'Meny oppdatert' })
        // this.$apollo.queries.menus.refresh()
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    async duplicateMenu (menu) {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation DuplicateMenu($menuId: ID!) {
              duplicateMenu(menuId: $menuId) {
                id
              }
            }
          `,
          variables: {
            menuId: menu.id
          },

          update: (store, { data: { duplicateMenu } }) => {
            this.$apollo.queries.menus.refresh()
          }
        })

        this.$toast.success({ message: this.$t('menus.menu-duplicated') })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    filter (items, item) {
      const result = items.filter(o => {
        if (o.items) o.items = this.filter(o.items, item)
        return o !== item
      })
      return result
    },

    async deleteItem (rootMenu, item) {
      this.$alerts.alertConfirm(
        'OBS',
        this.$t('menus.are-you-sure-you-want-to-delete-this-item'),
        async confirm => {
          if (!confirm) {
            return false
          } else {
            let menu = this.menus.find(m => parseInt(m.id) === parseInt(rootMenu.id))
            const idx = this.menus.indexOf(menu)
            menu = { ...menu, items: this.filter(menu.items, item) }

            this.menus = [
              ...this.menus.slice(0, idx),
              menu,
              ...this.menus.slice(idx + 1)
            ]

            this.saveMenu(menu)

            this.$apollo.queries.menus.refresh()
          }
        }
      )
    },

    async deleteEntry (entryId, override) {
      const fn = async () => {
        try {
          await this.$apollo.mutate({
            mutation: gql`
              mutation DeleteMenu($menuId: ID!) {
                deleteMenu(menuId: $menuId) {
                  id
                }
              }
            `,
            variables: {
              menuId: entryId
            }
          })

          this.$apollo.queries.menus.refresh()
          this.$toast.success({ message: this.$t('menus.menu-deleted') })
        } catch (err) {
          this.$utils.showError(err)
        }
      }

      if (override) {
        fn()
      } else {
        this.$alerts.alertConfirm('OBS', this.$t('menus.delete-confirm'), async confirm => {
          if (!confirm) {
            return false
          } else {
            fn()
          }
        })
      }
    },

    deleteEntries (entries, clearSelection) {
      this.$alerts.alertConfirm('OBS', this.$t('menus.delete-confirm-many'), async data => {
        if (!data) {
          return
        }

        entries.forEach(async id => {
          this.deleteEntry(id, true)
        })

        clearSelection()
      })
    }
  },

  apollo: {
    menus: {
      query: GET_MENUS,
      fetchPolicy: 'no-cache',
      variables () {
        return this.queryVars
      }
    }
  },

  i18n: {
    sharedMessages: locale
  }
}
</script>

<style lang="postcss" scoped>
  /* .title {
    @fontsize base(0.8);
    font-family: theme(typography.families.mono);
  } */

  .arrow {
    margin-right: 15px;
    opacity: 0.3;
  }

  .subtitle {
    @fontsize base(0.8);
    /* font-family: theme(typography.families.mono); */
    display: flex;
    flex-direction: row;
  }

  .badge {
    text-transform: none;
    margin-top: 5px;
  }

  .clickable {
    cursor: pointer;
  }
</style>
