<template>
  <div>
    <ContentHeader>
      <template #title>
        {{ $t('title') }}
      </template>
      <template #subtitle>
        {{ $t('subtitle') }}
      </template>
      <template #help>
        <p>
          {{ $t('help') }}
        </p>
      </template>
    </ContentHeader>

    <p class="help">
      {{ $t('help-more') }}
    </p>

    <table>
      <tr
        v-for="job in jobs"
        :key="`${job.args.id}${job.args.schema}`">
        <td class="state fit">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="15"
            height="15"
            viewBox="0 0 15 15">
            <circle
              :class="job.state"
              r="7.5"
              cy="7.5"
              cx="7.5" />
          </svg>
        </td>
        <td>
          <strong>{{ job.meta.identifier.title }}</strong><br>
          <small>{{ job.meta.identifier.type }}#{{ job.meta.identifier.id }}</small>
        </td>
        <td class="fit date">
          {{ fdt(job.scheduled_at) }}
        </td>
        <td class="fit">
          <ButtonSecondary
            @click="deleteJob(job)">
            {{ $t('delete-job') }}
          </ButtonSecondary>
        </td>
      </tr>
    </table>

    <ButtonPrimary
      @click="refreshQueue">
      {{ $t('refresh-jobs') }}
    </ButtonPrimary>
  </div>
</template>

<script>
import { parseISO } from 'date-fns'
import { format } from 'date-fns-tz'

export default {
  inject: [
    'adminChannel',
    'GLOBALS'
  ],

  data () {
    return {
      loading: 0,
      jobs: []
    }
  },

  async created () {
    this.loading++
    this.loading--
  },

  mounted () {
    this.getQueue()
  },

  methods: {
    fdt (dt) {
      return format(parseISO(dt), 'dd.MM.yy @ HH:mm (z)', { timeZone: this.GLOBALS.identity.config.timezone })
    },

    deleteJob (job) {
      this.adminChannel.channel
        .push('publisher:delete_job', { job })
        .receive('ok', () => {
          this.$toast.success({ message: this.$t('job-deleted') })
          this.getQueue()
        })
    },

    getQueue () {
      this.adminChannel.channel
        .push('publisher:list', {})
        .receive('ok', result => { this.jobs = result.jobs })
    },

    refreshQueue () {
      this.$toast.success({ message: this.$t('fetching-jobs') })
      this.getQueue()
    }
  }
}
</script>
<style lang="postcss" scoped>
  .help {
    @column 10/16;
    @space padding-bottom 20px;
  }

  table {
    @column 1/1;
    @space margin-bottom 35px;
    @space margin-top 10px;

    h1 {
      @space margin-bottom 20px;
      text-transform: capitalize;
    }

    td {
      border: 1px solid;
      padding: 10px 15px;

      small {
        @font mono;
        @fontsize base(0.8);
      }

      &.date {
        @font mono;
        @fontsize base(0.8);
      }

      &.state {
        svg {
          circle {
            fill: theme(colors.blue);

            &.retryable {
              fill: theme(colors.status.draft);
            }

            &.scheduled {
              fill: theme(colors.status.pending);
            }

            &.completed, &.executing {
              fill: theme(colors.status.published);
            }

            &.discarded {
              fill: theme(colors.status.disabled);
            }
          }
        }
      }
    }
  }

  button + button {
    @space margin-left 15px;
  }

</style>
<i18n>
  {
    "en": {
      "title": "Planned Publishing",
      "subtitle": "View and administrate content publishing queue",
      "help-more": "This is a list of planned content publishing",
      "fetching-jobs": "Fetching content queue",
      "refresh-jobs": "Refresh content queue",
      "delete-job": "Delete scheduled change",
      "job-deleted": "Scheduled change was deleted"
    },
    "no": {
      "title": "Planlagt publisering",
      "subtitle": "Administrér innholdskø",
      "help-more": "Under kan du finne en liste over planlagte publiseringer.",
      "fetching-jobs": "Henter innholdskø",
      "refresh-jobs": "Oppdater innholdskø",
      "delete-job": "Slett planlagt endring",
      "job-deleted": "Planlagt endring slettet"
    }
  }
</i18n>
