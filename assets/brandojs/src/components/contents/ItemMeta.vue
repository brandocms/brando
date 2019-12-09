<template>
  <article class="item-meta">
    <section
      v-if="showAvatar"
      class="avatar-wrapper">
      <div class="avatar">
        <img :src="user.avatar ? user.avatar.thumb : '/images/admin/avatar.png'" />
      </div>
    </section>
    <section class="content">
      <div class="info">
        <div class="name">
          {{ user.full_name || 'Systemroboten' }}
        </div>
        <div class="time">
          {{ getDate(entry.updated_at) }} <span>•</span> {{ getTime(entry.updated_at)}}
        </div>
      </div>
    </section>
  </article>
</template>

<script>

import moment from 'moment-timezone'

export default {
  props: {
    user: {
      type: Object,
      default: () => {}
    },

    entry: {
      type: Object,
      default: () => {}
    },

    showAvatar: {
      type: Boolean,
      default: true
    }
  },

  methods: {
    getDate (datetime) {
      return moment.tz(datetime, 'Europe/Oslo').format('DD.MM.YY')
    },

    getTime (datetime) {
      return moment.tz(datetime, 'Europe/Oslo').format('HH:mm')
    }
  }
}
</script>

<style lang="postcss" scoped>
  .item-meta {
    display: flex;
    align-items: center;

    .avatar-wrapper {
      align-items: center;
      display: flex;
      margin-right: 15px;

      .avatar {
        margin-left: 7px;
        width: 48px;
        height: 48px;

        img {
          user-select: none;
          border-radius: 48px;
        }
      }
    }

    .content {
      width: 100%;
      display: flex;
      line-height: 1;
      justify-content: space-between;
      padding-left: 15px;
      border-left: 1px solid;
      padding-top: 2px;

      .name {
        font-weight: normal;
        font-size: 18px;
        user-select: none;
      }

      .time {
        /* font-family: 'Maison Neue', monospace; */
        font-size: 14px;
        opacity: 70%;
        user-select: none;
        text-transform: uppercase;

        span {
          opacity: 0.2;
        }
      }
    }
  }
</style>
