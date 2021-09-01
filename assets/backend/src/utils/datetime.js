import { parseISO } from 'date-fns'
import { format, utcToZonedTime } from 'date-fns-tz'

export function datetime(dateTime, timeZone = 'Europe/Oslo', zoned = false) {
  let zonedTime
  if (dateTime === null) {
    return '<ingen dato/tid>'
  }
  if (zoned) {
    zonedTime = utcToZonedTime(parseISO(dateTime), timeZone)
  } else {
    zonedTime = parseISO(dateTime)
  }
  return format(zonedTime, 'dd.MM.yy, HH:mm', { timeZone })
}

export function date(d, timeZone = 'Europe/Oslo') {
  if (d === null) {
    return '<ingen dato>'
  }
  return format(parseISO(d), 'dd.MM.yy', { timeZone })
}

export function shortDate(date, timeZone = 'Europe/Oslo') {
  if (date === null) {
    return '<ingen dato>'
  }
  return format(parseISO(datetime), 'dd.MM.yy', { timeZone })
}