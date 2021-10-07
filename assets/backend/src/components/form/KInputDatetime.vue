<template>
  <KFieldBase
    :name="name"
    :label="label"
    :rules="rules"
    :compact="compact"
    :help-text="helpText"
    :value="value">
    <div class="wrapper">
      <VueFlatpickr
        :id="id"
        v-model="innerValue"
        :placeholder="placeholder"
        :options="opts"
        class="flatpickr" />
      <button
        class="button-clear"
        @click.self.prevent.stop="clear">
        {{ $t('clear') }}
      </button>
    </div>
  </KFieldBase>
</template>

<script>
import { formatISO } from 'date-fns'
import VueFlatpickr from '@jacobmischka/vue-flatpickr'
import { english } from "flatpickr/dist/l10n/default.js"

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
          enableTime: true,
          minuteIncrement: 15,
          time_24hr: true,
          altInput: true,
          altFormat: 'l j F, Y @ H:i',
          dateFormat: 'Z',
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
      required: false,
      default: null
    },

    compact: {
      type: Boolean,
      default: false
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
      default: null,
      require: true
    }
  },

  data () {
    return {
      innerValue: '',
      opts: {}
    }
  },

  computed: {
    id () {
      return this.name.replace('[', '_').replace(']', '_')
    }
  },

  watch: {
    innerValue (value) {
      if (value === '') {
        value = null
      }
      this.$emit('input', value)
    },

    value (value) {
      this.innerValue = value
    }
  },

  created () {
    this.opts = {
      ...this.dateTimeOptions,
      locale: this.GLOBALS.me.language === 'en' ? english : LOCALE_NO,
    }

    this.innerValue = this.value

    if (!this.innerValue) {
      if (!this.null) {
        this.innerValue = formatISO(Date.now())
      }
    }
  },

  methods: {
    clear () {
      this.innerValue = null
    }
  }
}
</script>

<style lang="postcss">

  .wrapper {
    position: relative;
  }

  .button-clear {
    @fontsize sm/1;
    position: absolute;
    top: 7px;
    right: 15px;
    border: 1px solid theme(colors.dark);
    padding: 8px 12px 10px;
    transition: all 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.input);
    }
  }
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
<i18n>
  {
    "en": {
      "clear": "Clear"
    },
    "no": {
      "clear": "Slett"
    }
  }
</i18n>
