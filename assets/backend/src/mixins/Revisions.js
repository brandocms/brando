/**
 * Revisions mixin
 *
 * import Revisions from 'brandojs/src/mixins/Revisions'
 *
 * export default {
 *   mixins: [
 *     Revisions({
 *       schema: 'Brando.Pages.Page',
 *       prop: 'page',
 *       key: 'id
 *     })
 *   ],
 *
 * @param {*} param0
 */

import GET_REVISIONS from '../gql/revisions/REVISIONS_QUERY.graphql'

export default function ({ schema, prop, key }) {
  return {
    inject: [
      'adminChannel'
    ],

    computed: {
      hasId () {
        return this[prop][key]
      }
    },

    data () {
      return {
        revisionMeta: {
          schema,
          prop,
          key
        },
        revisionsInitialRun: true,
        activeRevision: {},
        revisionSet: false
      }
    },

    methods: {
      selectRevision (revision) {
        this.activeRevision = revision
        this.$parent.queryVars = { ...this.$parent.queryVars, revision: revision.revision }
        this.$parent.$apollo.queries[this.revisionMeta.prop].refresh()
      },

      activateRevision (revision) {
        this.adminChannel.channel
          .push('revision:activate', { schema: this.revisionMeta.schema, id: this[prop][key], revision: revision.revision })
          .receive('ok', payload => {
            this.selectRevision(revision)
            this.$apollo.queries.revisions.refresh()
          })
      },

      toggleProtected (revision) {
        const action = revision.protected ? 'unprotect' : 'protect'
        this.adminChannel.channel
          .push(`revision:${action}`, { schema: this.revisionMeta.schema, id: this[prop][key], revision: revision.revision })
          .receive('ok', payload => {
            this.$apollo.queries.revisions.refresh()
          })
      },

      describeRevision(revision, description) {
        this.adminChannel.channel
          .push('revision:describe', { schema: this.revisionMeta.schema, id: this[prop][key], revision: revision.revision, description: description })
          .receive('ok', payload => {
            this.$apollo.queries.revisions.refresh()
          })
      },

      schedulePublishing (revision, publishAt) {
        this.adminChannel.channel
          .push('revision:schedule', { schema: this.revisionMeta.schema, id: this[prop][key], revision: revision.revision, publish_at: publishAt })
          .receive('ok', payload => {
            this.$apollo.queries.revisions.refresh()
          })
      },

      deleteRevision (revision) {
        this.adminChannel.channel
          .push('revision:delete', { schema: this.revisionMeta.schema, id: this[prop][key], revision: revision.revision })
          .receive('ok', payload => {
            this.$apollo.queries.revisions.refresh()
          })
      },

      purgeRevisions () {
        this.adminChannel.channel
          .push('revisions:purge_inactive', { schema: this.revisionMeta.schema, id: this[prop][key] })
          .receive('ok', payload => {
            this.$apollo.queries.revisions.refresh()
          })
      }
    },

    apollo: {
      revisions: {
        query: GET_REVISIONS,
        fetchPolicy: 'no-cache',
        variables () {
          return {
            filter: { entry_type: schema, entry_id: this[prop][key] }
          }
        },

        update ({ revisions }) {
          if (this.revisionsInitialRun) {
            this.activeRevision = revisions.find(r => r.active)
            this.revisionsInitialRun = false
          }
          return revisions
        },

        skip () {
          if (this.revisionSet) {
            return true
          }
          if (!this[prop]) {
            return true
          }
          if (!this[prop][key]) {
            return true
          }
          return !this[prop][key]
        }
      }
    }
  }
}
