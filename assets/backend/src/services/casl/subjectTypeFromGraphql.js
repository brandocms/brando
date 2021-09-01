import { detectSubjectType } from '@casl/ability'

export default (subject) => {
  if (subject && typeof subject === 'object') {
    return subject.__typename
  }

  return detectSubjectType(subject)
}
