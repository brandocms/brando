export default [
  {
    text: 'MENY TEKST',
    icon: 'fal fa-dollar-sign fa-fw',
    children: [
      {
        text: 'Oversikt',
        to: { name: '<%= plural %>' }
      },

      {
        text: 'Legg til',
        to: { name: '<%= singular %>-new' }
      }
    ]
  }
]
