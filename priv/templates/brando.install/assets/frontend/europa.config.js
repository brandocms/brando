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
      base: '20px',

      /* line heights per breakpoint */
      lineHeight: {
        iphone: 1.5,
        mobile: 1.5,
        ipad_portrait: 1.5,
        ipad_landscape: 1.5,
        desktop_md: 1.5,
        desktop_lg: 1.5,
        desktop_xl: 1.5
      },

      /* main font sizing map */
      sizes: {
        /* this is per SIZE followed by per BREAKPOINT */
        base: {
          iphone: '16px',
          mobile: 'between(18px-24px)',
          ipad_portrait: 'between(20px-24px)',
          ipad_landscape: 'between(20px-22px)',
          desktop_md: 'between(22px-24px)',
          desktop_lg: 'between(24px-28px)',
          desktop_xl: '30px'
        },

        xl: {
          iphone: '30px',
          mobile: 'between(40px-60px)',
          ipad_portrait: 'between(60px-68px)',
          ipad_landscape: 'between(68px-78px)',
          desktop_md: 'between(78px-88px)',
          desktop_lg: 'between(88px-100px)',
          desktop_xl: '110px'
        }
      },

      sections: {
        navigation: {
          iphone: '34px',
          mobile: '34px',
          ipad_portrait: '42px',
          ipad_landscape: '20px',
          desktop_md: '20px',
          desktop_lg: '20px',
          desktop_xl: '20px',
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
        iphone: '18px',
        mobile: 'between(20px-30px)',
        ipad_portrait: 'between(30px-35px)',
        ipad_landscape: 'between(35px-45px)',
        desktop_md: 'between(50px-58px)',
        desktop_lg: 'between(58px-66px)',
        desktop_xl: '66px'
      },

      xs: {
        iphone: '15px',
        mobile: 'between(15px-18px)',
        ipad_portrait: 'between(18px-20px)',
        ipad_landscape: 'between(20px-25px)',
        desktop_md: 'between(25px-35px)',
        desktop_lg: 'between(35px-45px)',
        desktop_xl: '50px'
      }
    },

    header: {
      sections: {
        brand: {
          iphone: {
            width: '100px',
            height: '100px'
          },
          mobile: {
            width: '100px',
            height: '100px'
          },
          ipad_portrait: {
            width: '100px',
            height: '100px'
          },
          ipad_landscape: {
            width: '100px',
            height: '100px'
          },
          desktop_md: {
            width: '100px',
            height: '100px'
          },
          desktop_lg: {
            width: '100px',
            height: '100px'
          },
          desktop_xl: {
            width: '100px',
            height: '100px'
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
