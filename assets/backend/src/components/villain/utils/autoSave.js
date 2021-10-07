import getTimeStamp from './getTimestamp'
import { AUTOSAVE_MAX_SAVES } from '../config/autoSave.js'

function buildStorageKey () {
  return `VE-AUTOSAVE-${document.location}`
}

export function getAutoSaves () {
  const autoSaves = window.localStorage.getItem(buildStorageKey()) || '[]'
  return JSON.parse(autoSaves)
}

export function load () {
  var json = window.localStorage.getItem(buildStorageKey()) || JSON.stringify('')
  return JSON.parse(json)
}

export function addAutoSave (content) {
  const autoSaves = [
    {
      timestamp: getTimeStamp(),
      content: content
    },
    ...getAutoSaves()
  ]

  window.localStorage.setItem(
    buildStorageKey(),
    JSON.stringify(autoSaves.slice(0, AUTOSAVE_MAX_SAVES))
  )
}
