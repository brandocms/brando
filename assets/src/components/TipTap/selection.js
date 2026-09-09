export function captureRange(editor, range = editor.state.selection) {
  return { from: range.from, to: range.to, original: editor.state.doc.slice(range.from, range.to), valid: true }
}
export function mapRange(range, transaction) {
  if (!range || !range.valid || !transaction.docChanged) return range
  const start = transaction.mapping.mapResult(range.from, 1)
  const end = transaction.mapping.mapResult(range.to, -1)
  const valid = !start.deletedAcross && !end.deletedAcross && start.pos <= end.pos && transaction.doc.slice(start.pos, end.pos).eq(range.original)
  return { ...range, from: start.pos, to: end.pos, valid }
}
