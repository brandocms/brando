<template>
  <ValidationProvider
    v-slot="{ errors, invalid }"
    :name="name"
    :immediate="true"
    :rules="rules">
    <div :class="{'form-group': true, 'has-danger': invalid }">
      <div class="label-wrapper">
        <label
          :for="id"
          class="control-label">
          {{ label }}
        </label>
        <span v-if="invalid">
          <i class="fa fa-exclamation-circle text-danger" />
          {{ errors[0] }}
        </span>
      </div>

      <VueFlatpickr
        :id="id"
        v-model="innerValue"
        :placeholder="placeholder"
        :options="dateTimeOptions"
        class="form-control" />
    </div>
  </ValidationProvider>
</template>

<script>
import moment from 'moment-timezone'
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

  props: {
    dateTimeOptions: {
      type: Object,
      default: () => {
        return {
          enableTime: false,
          locale: LOCALE_NO,
          altInput: true,
          altFormat: 'l j F, Y',
          dateFormat: 'Y-m-d'
        }
      }
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
      default: () => {
        return moment.tz('Europe/Oslo').format()
      }
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
  }
}
</script>
