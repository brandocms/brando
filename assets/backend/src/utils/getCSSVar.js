export default function getCSSVar (el, varName) {
  const styles = window.getComputedStyle(el)
  return styles.getPropertyValue(varName)
}
