/**
 * ScheduledPublishing mixin
 *
 * import ScheduledPublishing from 'brandojs/src/mixins/ScheduledPublishing'
 *
 * export default {
 *   mixins: [
 *     ScheduledPublishing({ prop: 'page' })
 *   ],
 *
 */

import { differenceInSeconds, parseISO } from 'date-fns'
import { format } from 'date-fns-tz'

export default function ({ prop }) {
  return {
    inject: [
      'adminChannel',
      'GLOBALS'
    ],

    computed: {
      publishInFuture () {
        let publishAt = this[prop] ? this[prop]['publishAt'] : null
        let now = Date.now()

        return (differenceInSeconds(parseISO(publishAt), now) > 0)
      },

      scheduledPublishingStatus () {
        const status = this[prop] ? this[prop]['status'] : null
        let publishAt = this[prop] ? this[prop]['publishAt'] : null

        if (!status && !publishAt) {
          // probably not ready yet
          return null
        }

        let now = Date.now()
        let futureDate = false

        if (publishAt) {
          futureDate = (differenceInSeconds(parseISO(publishAt), now) > 0)
          publishAt = format(parseISO(publishAt), 'dd.MM.yy @ HH:mm (z)', { timeZone: this.GLOBALS.identity.config.timezone })
        }

        if (futureDate) {
          return { status: 'pending', message: 'pending_at', args: { publishAt } }
        }

        if (status === 'published' && publishAt) {
          return { status: 'published', message: 'published_at', args: { publishAt } }
        }

        if (status === 'published') {
          if (this[prop]['id']) {
            return { status: 'published', message: 'published', args: { publishAt } }
          }
          return { status: 'published', message: 'published_on_save', args: {} }
        }

        if (status === 'pending' && publishAt) {
          return { status: 'pending', message: 'pending_at', args: { publishAt } }
        }

        if (status === 'pending') {
          return { status: 'pending', message: 'pending', args: {} }
        }

        if (status === 'draft' && publishAt) {
          return { status: 'draft', message: 'draft', args: { publishAt } }
        }

        if (status === 'draft') {
          return { status: 'draft', message: 'draft', args: {} }
        }

        if (status === 'disabled') {
          return { status: 'disabled', message: 'disabled', args: {} }
        }

        return null
      }
    },

    data () {
      return {
        scheduledPublishing: {
          prop
        }
      }
    },

    methods: {
      checkScheduledPublishingStatus () {
        if (this[prop]['status'] !== 'pending' && this.publishInFuture) {
          this[prop]['status'] = 'pending'
          return false
        }
        return true
      }
    }
  }
}