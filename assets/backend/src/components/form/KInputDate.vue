<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :help-text="helpText"
    :value="value">
    <VueFlatpickr
      :id="id"
      v-model="innerValue"
      :placeholder="placeholder"
      :options="dateTimeOptions"
      class="flatpickr" />
  </KFieldBase>
</template>

<script>
import { format } from 'date-fns-tz'
import VueFlatpickr from '@jacobmischka/vue-flatpickr'

const LOCALE_NO = {
  weekdays: {
    shorthand: ['Søn', 'Man', 'Tir', 'Ons', 'Tor', 'Fre', 'Lør'],
    longhand: [
      'Søndag',
      'Mandag',
      'Tirsdag',
      'Onsdag',
      'Torsdag',
      'Fredag',
      'Lørdag'
    ]
  },
  months: {
    shorthand: [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ],
    longhand: [
      'Januar',
      'Februar',
      'Mars',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Desember'
    ]
  },
  firstDayOfWeek: 1,
  rangeSeparator: ' til ',
  weekAbbreviation: 'Uke',
  scrollTitle: 'Scroll for å endre',
  toggleTitle: 'Klikk for å veksle',
  ordinal: function () {
    return '.'
  }
}

export default {
  components: {
    VueFlatpickr
  },

  inject: ['GLOBALS'],

  props: {
    dateTimeOptions: {
      type: Object,
      default: () => {
        return {
          enableTime: false,
          locale: LOCALE_NO,
          altInput: true,
          altFormat: 'l j F, Y',
          dateFormat: 'Y-m-d',
          allowInput: true
        }
      }
    },

    null: {
      type: Boolean,
      default: false
    },

    helpText: {
      type: String,
      default: null
    },

    rules: {
      type: String,
      default: null
    },

    label: {
      type: String,
      required: true
    },

    placeholder: {
      type: String,
      required: false,
      default: ''
    },

    name: {
      type: String,
      required: true
    },

    value: {
      type: String,
      required: true
    }
  },

  data () {
    return {
      innerValue: ''
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    }
  },

  watch: {
    innerValue (value) {
      this.$emit('input', value)
    },

    value (value) {
      this.innerValue = value
    }
  },

  created () {
    this.innerValue = this.value

    if (!this.innerValue) {
      if (!this.null) {
        this.innerValue = format(Date.now(), 'yyyy-MM-dd', { timeZone: this.GLOBALS.identity.config.timezone })
      }
    }
  }
}
</script>

<style lang="postcss">
  .flatpickr-day.selected {
    background-color: theme(colors.blue);
    border-color: theme(colors.blue);
  }

  .flatpickr-current-month .flatpickr-monthDropdown-months {
    font-weight: 400;
  }

  .flatpickr-current-month input.cur-year {
    font-weight: 400;
  }

  .flatpickr {
    @fontsize base;
    padding-top: 12px;
    padding-bottom: 12px;
    padding-left: 15px;
    padding-right: 15px;
    width: 100%;
    background-color: theme(colors.input);
    border: 0;

    &.monospace {
      @fontsize base(0.8);
      font-family: theme(typography.families.mono);
      padding-bottom: 12px;
      padding-top: 16px;
    }
  }
</style>
