import clone from 'lodash/cloneDeep'
import diff from './diff'
import pick from './pick'
import showError from './showError'
import validateFileParams from './validateFileParams'
import validateImageParams from './validateImageParams'
import validateImageSeriesParams from './validateImageSeriesParams'
import serializeParams from './serializeParams'
import stripParams from './stripParams'
import stripImageSeriesParams from './stripImageSeriesParams'
import removeTypename from './removeTypename'
import stripTypenames from './stripTypenames'
import guid from './guid'
import wait from './wait'
import humanFilesize from './humanFilesize'
import jaroDistance from './jaroDistance'
import mapMultiSelect from './mapMultiSelect'
import mapMultiSelects from './mapMultiSelects'
import si from 'shortid'
import { datetime, date, shortDate } from './datetime'

function shortid () {
  return si.generate()
}

export const utils = {
  pick,
  clone,
  diff,
  guid,
  wait,
  shortid,
  jaroDistance,
  showError,
  humanFilesize,
  mapMultiSelect,
  mapMultiSelects,
  validateFileParams,
  validateImageParams,
  validateImageSeriesParams,
  serializeParams,
  stripParams,
  stripImageSeriesParams,
  removeTypename,
  stripTypenames,
  datetime,
  date,
  shortDate
}
