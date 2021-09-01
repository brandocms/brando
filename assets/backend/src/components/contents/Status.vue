<template>
  <div
    ref="button"
    @click.prevent.stop="toggle">
    <svg
      v-if="isWaiting"
      v-popover="$t('publish-at') + publishTime"
      :data-testid="`status-${status}`"
      width="15"
      height="15"
      viewBox="0 0 15 15"
      fill="none"
      xmlns="http://www.w3.org/2000/svg">
      <circle
        :class="status"
        cx="7.5"
        cy="7.5"
        r="7.5" />
      <line
        x1="7.5"
        y1="3"
        x2="7.5"
        y2="7"
        stroke="white" />
      <line
        x1="3.5"
        y1="7.5"
        x2="8"
        y2="7.5"
        stroke="white" />
    </svg>

    <svg
      v-else
      :data-testid="`status-${status}`"
      xmlns="http://www.w3.org/2000/svg"
      width="15"
      height="15"
      viewBox="0 0 15 15">
      <circle
        :class="status"
        r="7.5"
        cy="7.5"
        cx="7.5" />
    </svg>
    <slot></slot>
    <ul
      ref="content"
      data-testid="status-dropdown-content"
      class="dropdown-content"
      @click.stop="closeContent">
      <li>
        <button
          v-if="status !== 'published'"
          type="button"
          @click="setStatus('published')">
          {{ $t('published') }}
        </button>
        <button
          v-if="status !== 'draft'"
          type="button"
          @click="setStatus('draft')">
          {{ $t('draft') }}
        </button>
        <button
          v-if="status !== 'disabled'"
          type="button"
          @click="setStatus('disabled')">
          {{ $t('disabled') }}
        </button>
      </li>
    </ul>
  </div>
</template>

<script>
import { differenceInSeconds, parseISO } from 'date-fns'
import { format } from 'date-fns-tz'
import { gsap } from 'gsap'
import gql from 'graphql-tag'

export default {

  inject: ['GLOBALS'],
  props: {
    entry: {
      type: Object,
      required: true
    }
  },

  data () {
    return {
      now: null,
      open: false
    }
  },

  computed: {
    publishTime () {
      if (this.entry.publishAt) {
        return format(parseISO(this.entry.publishAt), 'dd.MM.yy @ HH:mm (z)', { timeZone: this.GLOBALS.identity.config.timezone })
      }
      return null
    },

    isWaiting () {
      if (!this.entry.publishAt) {
        return false
      }

      return (differenceInSeconds(parseISO(this.entry.publishAt), this.now) > 0)
    },

    status () {
      if (this.entry.publishAt && ['published', 'pending'].includes(this.entry.status)) {
        if (differenceInSeconds(parseISO(this.entry.publishAt), this.now) < 0) {
          return 'published'
        } else {
          return 'pending'
        }
      }

      return this.entry.status
    }
  },

  created () {
    this.getNow()
    setInterval(this.getNow, 5000)
  },

  destroyed () {
    clearInterval(this.getNow)
  },

  methods: {
    async setStatus (status) {
      try {
        await this.$apollo.mutate({
          mutation: gql`
            mutation UpdateEntryStatus($id: ID!, $schema: String!, $status: String!) {
              updateEntryStatus(
                id: $id,
                schema: $schema,
                status: $status
              ) {
                id
                status
              }
            }
          `,
          variables: {
            id: this.entry.id,
            schema: this.entry.__typename,
            status
          }
        })
      } catch (err) {
        this.$utils.showError(err)
      }
    },

    getNow () {
      this.now = Date.now()
    },

    toggle () {
      return
      // if (this.open) {
      //   this.closeContent()
      // } else {
      //   this.openContent()
      // }
    },

    openContent () {
      this.open = true
      const buttonHeight = this.$refs.button.clientHeight
      gsap.set(this.$refs.content, { top: buttonHeight + 10, left: 0, opacity: 0, x: -15, display: 'block' })
      // find out where we are
      const buttonBottom = this.$refs.button.getBoundingClientRect().y + buttonHeight
      const contentRect = this.$refs.content.getBoundingClientRect()
      if (contentRect.height + buttonBottom > window.innerHeight) {
        gsap.set(this.$refs.content, { top: (contentRect.height + 10) * -1 })
      }
      gsap.to(this.$refs.content, { opacity: 1, x: 0, duration: 0.35 })
    },

    closeContent () {
      if (this.open) {
        this.open = false
        if (this.$refs.content) {
          gsap.to(this.$refs.content, {
            opacity: 0,
            x: -15,
            duration: 0.35,
            onComplete: () => {
              if (this.$refs.content) {
                gsap.set(this.$refs.content, { display: 'none' })
              }
            }
          })
        }
      }
    }
  }
}
</script>

<style lang="postcss" scoped>
  div {
    display: flex;
    border: 1px solid transparent;
    transition: border-color 350ms ease;
    margin-left: -1px;
    border-radius: 50%;

    &:hover {
      cursor: pointer;
      border: 1px solid theme(colors.dark);
    }
  }

  .dropdown-content {
    display: none;
    opacity: 0;
    background-color: theme(colors.peach);
    color: theme(colors.dark);
    position: absolute;
    width: 175px;
    border: 1px solid theme(colors.dark);
    z-index: 2;

    li {
      a, button {
        @font mono;
        display: block;
        padding: 15px;
        text-align: right;
        line-height: 1;
        border: none;
        float: right;
        width: 100%;
        font-size: 15px;
        text-transform: uppercase;

        &:hover {
          background-color: theme(colors.dark);
          color: theme(colors.peach);
        }
      }
    }
  }

  svg {
    border: 3px solid #fff;
    border-radius: 50%;
    box-sizing: content-box;

    circle {
      fill: theme(colors.blue);

      &.draft {
        fill: theme(colors.status.draft);
      }

      &.pending {
        fill: theme(colors.status.pending);
      }

      &.published {
        fill: theme(colors.status.published);
      }

      &.disabled {
        fill: theme(colors.status.disabled);
      }
    }
  }
</style>
<i18n>
  {
    "en": {
      "publish-at": "Publish at ",
      "draft": "Draft",
      "disabled": "Disabled",
      "published": "Published",
      "pending": "Pending"
    },
    "no": {
      "publish-at": "Publiseres ",
      "draft": "Utkast",
      "disabled": "Deaktivert",
      "published": "Publisert",
      "pending": "Venter"
    }
  }
</i18n>
