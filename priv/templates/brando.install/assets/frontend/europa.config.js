module.exports = {
  theme: {
    breakpoints: {
      iphone: '0',
      mobile: '480px',
      ipad_portrait: '768px',
      ipad_landscape: '1024px',
      desktop_md: '1200px',
      desktop_lg: '1440px',
      desktop_xl: '1920px'
    },

    breakpointCollections: {
      $mobile: '<=mobile',
      $tablet: 'ipad_portrait/ipad_landscape',
      $desktop: '>=desktop_md',
      $lg: '>=ipad_landscape',
      $sm: '<=ipad_portrait'
    },

    colors: () => ({
      black: '#000000',
      white: '#ffffff',
      dark: '#2b2b2b',
      light: '#f9f7f4',
      transparent: 'transparent',
      dbg: 'pink',

      body: {
        foreground: '#000',
        background: '#fff'
      },

      link: {
        regular: {
          text: '#000000',
          border: '#000000',
        },
        hover: {
          text: '#000000',
          border: '#000000',
        },
      },

      gray: {
        900: '#858585'
      },

      fader: {
        background: '#f9f7f4',
        foreground: '#2b2b2b'
      },

      footer: {
        background: '#f9ece5'
      },

      header: {
        background: '#f9f7f4',
        foreground: '#000000'
      },

      navigation: {
        backgroundAlt: 'ghostwhite'
      }
    }),

    container: {
      maxWidth: {
        iphone: '100%',
        mobile: '100%',
        ipad_portrait: '100%',
        ipad_landscape: '100%',
        desktop_md: '100%',
        desktop_lg: '100%',
        desktop_xl: '100%'
      },

      padding: {
        iphone: '4.39453125vw',
        mobile: '4.39453125vw',
        ipad_portrait: '4.39453125vw',
        ipad_landscape: '4.39453125vw',
        desktop_md: '4.39453125vw',
        desktop_lg: '4.39453125vw',
        desktop_xl: '4.39453125vw'
      }
    },

    columns: {
      count: {
        iphone: 6,
        mobile: 6,
        ipad_portrait: 6,
        ipad_landscape: 12,
        desktop_md: 12,
        desktop_lg: 12,
        desktop_xl: 12
      },
      gutters: {
        iphone: '1.5vw',
        mobile: '1.5vw',
        ipad_portrait: '1.5vw',
        ipad_landscape: '1.5vw',
        desktop_md: '1.5vw',
        desktop_lg: '1.5vw',
        desktop_xl: '1.5vw'
      }
    },

    typography: {
      /* `base` is the px value of 1rem set as font-size on the html element. */
      base: '18px',

      /* line heights per breakpoint */
      lineHeight: {
        iphone: 1.4,
        mobile: 1.4,
        ipad_portrait: 1.4,
        ipad_landscape: 1.4,
        desktop_md: 1.4,
        desktop_lg: 1.4,
        desktop_xl: 1.4
      },

      /* main font sizing map */
      sizes: {
        /* this is per SIZE followed by per BREAKPOINT */
        base: {
          iphone: '16px',
          mobile: '17px',
          ipad_portrait: '17px',
          ipad_landscape: '17px',
          desktop_md: '18px',
          desktop_lg: '19px',
          desktop_xl: '22px'
        }
      },

      sections: {
        navigation: {
          iphone: {},
          mobile: {},

          desktop_md: {
            'font-size': '16px',
            'line-height': '12px'
          },

          desktop_lg: {
            'font-size': '18px',
            'line-height': '14px'
          },

          desktop_xl: {
            'font-size': '21px',
            'line-height': '15px'
          }
        }
      },

      families: {
        main: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          '"Helvetica Neue"',
          'Arial',
          'sans-serif'
        ],

        serif: [
          'Georgia',
          'Cambria',
          '"Times New Roman"',
          'Times',
          'serif'
        ],

        mono: [
          'Menlo',
          'Monaco',
          'Consolas',
          '"Liberation Mono"',
          '"Courier New"',
          'monospace'
        ]
      }
    },

    spacing: {
      block: {
        iphone: '55px',
        mobile: '55px',
        ipad_portrait: '55px',
        ipad_landscape: '55px',
        desktop_md: '55px',
        desktop_lg: '55px',
        desktop_xl: '55px'
      },
    },

    header: {
      sections: {
        brand: {
          iphone: {
            width: '100px',
            height: '81.05px'
          },
          mobile: {
            width: '100px',
            height: '81.05px'
          },
          ipad_portrait: {
            width: '100px',
            height: '81.05px'
          },
          ipad_landscape: {
            width: '100px',
            height: '81.05px'
          },
          desktop_md: {
            width: '100%',
            height: '100%'
          },
          desktop_lg: {
            width: '100%',
            height: '100%'
          },
          desktop_xl: {
            width: '100%',
            height: '100%'
          }
        }
      },

      padding: {
        /* When header is small */
        small: {
          iphone: {
            'padding-top': '30px',
            'padding-bottom': '30px'
          },
          mobile: {
            'padding-top': '30px',
            'padding-bottom': '30px'
          },
          ipad_portrait: {
            'padding-top': '40px',
            'padding-bottom': '40px'
          },
          ipad_landscape: {
            'padding-top': '40px',
            'padding-bottom': '40px'
          },
          desktop_md: {
            'padding-top': '40px',
            'padding-bottom': '35px'
          },
          desktop_lg: {
            'padding-top': '40px',
            'padding-bottom': '35px'
          },
          desktop_xl: {
            'padding-top': '60px',
            'padding-bottom': '60px'
          }
        },
        /* When header is large */
        large: {
          iphone: {
            'padding-top': '15px',
            'padding-bottom': '15px'
          },
          mobile: {
            'padding-top': '15px',
            'padding-bottom': '15px'
          },
          ipad_portrait: {
            'padding-top': '40px',
            'padding-bottom': '40px'
          },
          ipad_landscape: {
            'padding-top': '40px',
            'padding-bottom': '60px'
          },
          desktop_md: {
            'padding-top': '40px',
            'padding-bottom': '20px'
          },
          desktop_lg: {
            'padding-top': '70px',
            'padding-bottom': '35px'
          },
          desktop_xl: {
            'padding-top': '80px',
            'padding-bottom': '40px'
          }
        }
      }
    }
  }
}
