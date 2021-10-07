/**
 * Meta mixin
 *
 * import Meta from 'brandojs/src/mixins/Meta'
 *
 * export default {
 *   mixins: [
 *     Meta({ prop: 'page' })
 *   ],
 *
 */

export default function ({ prop }) {
  return {
    inject: [
      'adminChannel'
    ],

    computed: {
      metaScore () {
        const title = this[prop] ? this[prop]['metaTitle'] : null
        const description = this[prop] ? this[prop]['metaDescription'] : null
        const metaImage = this[prop] ? this[prop]['metaImage'] : null

        let score = 0

        if (title && title.length > 0 <= 70) {
          score += 5
        }

        if (description && description.length > 0 <= 155) {
          score += 5
        }

        if (metaImage) {
          score += 3
        }

        return score
      },

      metaScoreStatus () {
        if (this.metaScore === 0) {
          return 'draft'
        } else if (this.metaScore < 5) {
          return 'disabled'
        } else if (this.metaScore >= 10) {
          return 'published'
        } else {
          return 'pending'
        }
      }
    },

    data () {
      return {
        meta: {
          prop
        }
      }
    },

    methods: {
    }
  }
}