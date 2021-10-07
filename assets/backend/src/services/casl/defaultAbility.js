import { PureAbility } from '@casl/ability'
import subjectTypeFromGraphql from './subjectTypeFromGraphql'
import conditionsMatcher from './conditionsMatcher'

export default new PureAbility([], { detectSubjectType: subjectTypeFromGraphql, conditionsMatcher })
