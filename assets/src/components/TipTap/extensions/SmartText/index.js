import { ellipsis, smartQuotes, InputRule } from 'prosemirror-inputrules'
import { Extension } from '@tiptap/core'

const rightArrow = new InputRule(/->$/, '→')
const leftArrow = new InputRule(/<-$/, '←')
const oneHalf = new InputRule(/1\/2$/, '½')
const threeQuarters = new InputRule(/3\/4$/, '¾')
const copyright = new InputRule(/\(c\)$/, '©️')
const registered = new InputRule(/\(r\)$/, '®️')
const trademarked = new InputRule(/\(tm\)$/, '™️')

export default Extension.create({
  name: 'smartText',

  inputRules() {
    return [
      rightArrow,
      leftArrow,
      oneHalf,
      threeQuarters,
      copyright,
      registered,
      trademarked,
      ellipsis,
      ...smartQuotes
    ]
  }
})
