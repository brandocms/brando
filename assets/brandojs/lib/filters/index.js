import moment from 'moment-timezone'

export function datetime (dateTime) {
  if (dateTime === null) {
    return '<ingen dato/tid>'
  }
  return moment.tz(dateTime, 'Europe/Oslo').format('DD.MM.YYYY → HH:mm')
}

export function date (date) {
  if (date === null) {
    return '<ingen dato>'
  }
  return moment.tz(date, 'Europe/Oslo').format('DD.MM.YYYY')
}

export function shortDate (date) {
  if (date === null) {
    return '<ingen dato>'
  }
  return moment.tz(date, 'Europe/Oslo').format('DD.MM.YY')
}

export function formatSize (size) {
  if (size > 1024 * 1024 * 1024 * 1024) {
    return (size / 1024 / 1024 / 1024 / 1024).toFixed(2) + ' TB'
  } else if (size > 1024 * 1024 * 1024) {
    return (size / 1024 / 1024 / 1024).toFixed(2) + ' GB'
  } else if (size > 1024 * 1024) {
    return (size / 1024 / 1024).toFixed(2) + ' MB'
  } else if (size > 1024) {
    return (size / 1024).toFixed(2) + ' KB'
  }
  return size.toString() + ' B'
}

export function truncate (value, length) {
  if (!value) {
    return value
  }
  if (value.length < length) {
    return value
  }

  return `${value.substr(0, length)}...`
}
