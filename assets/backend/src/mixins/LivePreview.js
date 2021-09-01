import cloneDeep from 'lodash/cloneDeep'
import debounce from 'lodash/debounce'

export default function ({ schema, prop, key }) {
  return {
    data () {
      return {
        livePreview: true,
        livePreviewReady: false,
        livePreviewWrapper: null,
        livePreviewCacheKey: null,
        livePreviewPreviousValue: null,
        livePreviewFirstRun: true,
        livePreviewActivated: false
      }
    },

    watch: {
      [prop]: {
        deep: true,
        immediate: true,
        handler: debounce(function (v) {
          if (this.livePreview) {
            if (this.livePreviewReady && this.livePreviewActivated) {
              const changes = this.$utils.diff(v, this.livePreviewPreviousValue)
              this.updateLivePreview(changes)
              this.livePreviewPreviousValue = cloneDeep(v)
            }
          }
        }, 750, true)
      }
    },

    inject: [
      'adminChannel'
    ],

    methods: {
      sharePreview (revision = null) {
        if (!('id' in this[prop])) {
          this.$alerts.alertError('Delt forhåndsvisning', 'Man kan ikke dele et objekt som aldri har vært lagret. Prøv å lagre som utkast før du deler!')
          return false
        }
        let args = { schema, key, prop, id: this[prop].id }
        if (revision) {
          args = { ...args, revision: revision.revision }
        }

        this.adminChannel.channel
          .push('livepreview:share', args)
          .receive('ok', ({ preview_url }) => {
            this.$alerts.alertSuccess('Delt forhåndsvisning', `Her er din delte forhåndsvisnings URL:<br><br><a href="${preview_url}" target="_blank">Klikk her</a><br><br>Lenken er gyldig i 24 timer.`)
          })
      },

      openLivePreview () {
        this.livePreviewPreviousValue = cloneDeep(this[prop])
        this.adminChannel.channel
          .push('livepreview:initialize', { schema, prop, key, entry: this[prop] })
          .receive('ok', payload => {
            if (payload.cache_key) {
              this.livePreviewCacheKey = payload.cache_key
              this.livePreviewReady = true

              window.open(
                '/__livepreview?key=' + this.livePreviewCacheKey,
                '_blank'
              )

              this.livePreviewActivated = true
            } else {
              this.livePreviewReady = false
            }
          })
          .receive('error', resp => {
            this.$alerts.alertError('Feil', 'Live preview ikke støttet for denne typen')
            console.error(resp)
          })
      },

      updateLivePreview (entry) {
        if (!this.livePreviewReady) {
          return
        }

        if (!this.livePreviewActivated) {
          return
        }

        // send off entry for rendering
        this.adminChannel.channel
          .push('livepreview:render', { schema, prop, key, entry, cache_key: this.livePreviewCacheKey })
      }
    }
  }
}
