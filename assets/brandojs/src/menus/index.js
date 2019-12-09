export default [
  {
    name: 'System',
    items: [
      {
        name: 'Dashboard',
        to: {
          name: 'dashboard'
        }
      },
      {
        name: 'Konfigurasjon',
        items: [
          {
            text: 'Identitet',
            to: {
              name: 'config-identity'
            }
          }, {
            text: 'Innholdsmaler',
            to: {
              name: 'templates'
            }
          }
        ]
      }, {
        name: 'Brukere',
        to: {
          name: 'users'
        }
      }, {
        name: 'Bildebibliotek',
        to: {
          name: 'images'
        }
      }, {
        name: 'Filbibliotek',
        to: {
          name: 'files'
        }
      }
    ]
  },
  {
    name: 'Content',
    items: [
      {
        name: 'Sider & seksjoner',
        to: {
          name: 'pages'
        }
      }
    ]
  }
]
