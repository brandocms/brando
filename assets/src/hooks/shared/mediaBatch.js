// Sorting a batch of dropped or picked files into images and videos, and
// refusing the ones a destination cannot take, before anything uploads.
//
// `kinds` says what the destination takes, by kind; a kind left out takes
// nothing:
//
//   { image: { extensions: ['.jpg', …], mimetypes: ['image/jpeg', …] | null, limit: 4000000 | null },
//     video: { … } }
//
// `mimetypes` null takes any type. A block ref's kinds come from its upload
// field (`MediaField.upload_policy/2`), which turns a config's `["*"]` into
// null.
//
// The upload manager checks everything again at intake: this only spares
// the editor an entry or a block for a file that would be refused.

export function extension(file) {
  const parts = file.name.split('.')
  return parts.length > 1 ? `.${parts.pop().toLowerCase()}` : ''
}

// Extension first: a .mov can arrive with an empty or lying MIME type, and
// the extension lists are what intake validates against. With `byExtension`
// a file goes only by its extension, as the upload manager's intake takes
// it; without, a file with an unlisted extension goes by its MIME type.
export function classify(file, kinds, { byExtension = false } = {}) {
  const ext = extension(file)
  const takes = (kind) => !!kinds[kind]
  const listed = (kind) => (kinds[kind].extensions || []).includes(ext)

  const kind =
    ['image', 'video'].find((k) => takes(k) && listed(k)) ||
    (!byExtension && ['image', 'video'].find((k) => takes(k) && file.type.startsWith(`${k}/`)))

  if (!kind) return null
  const mimetypes = kinds[kind].mimetypes
  if (mimetypes && mimetypes.length && file.type && !mimetypes.includes(file.type)) return null
  return kind
}

// `{ file, kind }`, or `{ rejected: { filename, reason: 'type' | 'size', limit } }`
export function validate(file, kinds, options = {}) {
  const kind = classify(file, kinds, options)
  if (!kind) return { rejected: { filename: file.name, reason: 'type' } }

  const limit = kinds[kind].limit
  if (limit && file.size > limit) return { rejected: { filename: file.name, reason: 'size', limit } }

  return { file, kind }
}

// The files `kinds` takes, in the order given, and the ones it refuses
// (`options` as for `classify`)
export function partition(files, kinds, options = {}) {
  const accepted = []
  const rejected = []

  files.forEach((file) => {
    const entry = validate(file, kinds, options)
    if (entry.rejected) rejected.push(entry.rejected)
    else accepted.push(entry)
  })

  return { accepted, rejected }
}

export function humanSize(bytes) {
  if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GB`
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${bytes} bytes`
}
