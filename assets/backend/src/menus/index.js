export default {
  no: [
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
          to: {
            name: 'config'
          },
          items: [
            {
              text: 'Identitet',
              to: {
                name: 'config-identity'
              }
            },
            {
              text: 'SEO',
              to: {
                name: 'config-seo'
              }
            },
            {
              text: 'Globale variabler',
              to: {
                name: 'config-globals'
              }
            },
            {
              text: 'Planlagt publisering',
              to: {
                name: 'config-publisher'
              }
            },
            {
              text: 'Hurtigbuffere',
              to: {
                name: 'config-cache'
              }
            },
            {
              text: 'Innholdsmoduler',
              to: {
                name: 'modules'
              }
            }
          ]
        },
        {
          name: 'Navigasjon',
          to: {
            name: 'navigation'
          }
        },
        {
          name: 'Brukere',
          to: {
            name: 'users'
          }
        },
        {
          name: 'Bildebibliotek',
          to: {
            name: 'images'
          }
        },
        {
          name: 'Filbibliotek',
          to: {
            name: 'files'
          }
        }
      ]
    },
    {
      name: 'Innhold',
      items: [
        {
          name: 'Sider & seksjoner',
          to: {
            name: 'pages'
          }
        }
      ]
    }
  ],

  en: [
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
          name: 'Configuration',
          items: [
            {
              text: 'Identity',
              to: {
                name: 'config-identity'
              }
            },
            {
              text: 'SEO',
              to: {
                name: 'config-seo'
              }
            },
            {
              text: 'Global variables',
              to: {
                name: 'config-globals'
              }
            },
            {
              text: 'Planned publishing',
              to: {
                name: 'config-publisher'
              }
            },
            {
              text: 'Cache',
              to: {
                name: 'config-cache'
              }
            },
            {
              text: 'Content modules',
              to: {
                name: 'modules'
              }
            }
          ]
        },
        {
          name: 'Navigation',
          to: {
            name: 'navigation'
          }
        },
        {
          name: 'Users',
          to: {
            name: 'users'
          }
        },
        {
          name: 'Image Library',
          to: {
            name: 'images'
          }
        },
        {
          name: 'File Library',
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
          name: 'Pages & Sections',
          to: {
            name: 'pages'
          }
        }
      ]
    }
  ]
}
