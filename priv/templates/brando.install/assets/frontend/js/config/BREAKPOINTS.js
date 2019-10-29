export default application => ({
  breakpoints: [
    'iphone',
    'mobile',
    'ipad_portrait',
    'ipad_landscape',
    'desktop_md',
    'desktop_lg',
    'desktop_xl'
  ],

  runListenerOnInit: true,

  listeners: {
    desktop_xl: mq => {}
  }
})
