import union from 'lodash/union'
import keys from 'lodash/keys'
import filter from 'lodash/filter'
import eq from 'lodash/eq'
import _toString from 'lodash/toString'

export default function diff (o1, o2) {
  const ks = union(keys(o1), keys(o2))
  return filter(ks, key => {
    if (typeof o1[key] === 'object' && o1[key] !== null && typeof o2[key] === 'object' && o2[key] !== null) {
      return !eq(JSON.stringify(o1[key]), JSON.stringify(o2[key]))
    }
    return !eq(_toString(o1[key]), _toString(o2[key]))
  }).reduce((p, c) => ({ ...p, [c]: o1[c] }), {})
}
