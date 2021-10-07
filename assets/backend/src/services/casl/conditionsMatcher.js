import isMatch from 'lodash/isMatch'
export default (ruleConditions) => {
  return (objectToTest) => {
    return isMatch(objectToTest, ruleConditions)
  }
}