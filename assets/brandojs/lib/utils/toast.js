import iziToast from 'izitoast'

iziToast.settings({
  position: 'topRight',
  title: '',
  animateInside: false,
  timeout: 5000,
  iconColor: '#ffffff',
  theme: 'kurtz'
})

export default function install (Vue) {
  Vue.prototype.$toast = iziToast
}
