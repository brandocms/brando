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
      $desktop: '>=desktop_md'
    },

    colors: () => ({
      dark: '#000000',
      light: '#f9f7f4',

      body: {
        background: '#fcf5f1'
      },

      link: {
        regular: '#000000',
        hover: '#000000',
        hoverBorder: '#000000'
      },

      gray: {
        900: '#858585'
      },

      fader: {
        background: '#f9f7f4',
        foreground: 'rgb(143, 143, 143)'
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
        iphone: '15px',
        mobile: '15px',
        ipad_portrait: '40px',
        ipad_landscape: '60px',
        desktop_md: '70px',
        desktop_lg: '90px',
        desktop_xl: '110px'
      }
    },

    columns: {
      count: {
        iphone: 6,
        mobile: 6,
        ipad_portrait: 12,
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
        iphone: 1.6,
        mobile: 1.6,
        ipad_portrait: 1.6,
        ipad_landscape: 1.6,
        desktop_md: 1.6,
        desktop_lg: 1.6,
        desktop_xl: 1.6
      },

      /* paddingDivider is used to set column-typography right padding.
         Lower values = more padding */
      paddingDivider: 8,

      /* main font sizing map */
      sizes: {
        /* this is per SIZE followed by per BREAKPOINT */
        '2xs': {
          iphone: '9px',
          mobile: '9px',
          ipad_portrait: '10px',
          ipad_landscape: '10px',
          desktop_md: '10px',
          desktop_lg: '12px',
          desktop_xl: '13px'
        },

        xs: {
          iphone: '12px',
          mobile: '12px',
          ipad_portrait: '12px',
          ipad_landscape: '12px',
          desktop_md: '12px',
          desktop_lg: '13px',
          desktop_xl: '14px'
        },

        sm: {
          iphone: '14px',
          mobile: '14px',
          ipad_portrait: '14px',
          ipad_landscape: '15px',
          desktop_md: '16px',
          desktop_lg: '17px',
          desktop_xl: '19px'
        },

        base: {
          iphone: '16px',
          mobile: '17px',
          ipad_portrait: '17px',
          ipad_landscape: '17px',
          desktop_md: '18px',
          desktop_lg: '20px',
          desktop_xl: '24px'
        },

        lg: {
          iphone: '18px',
          mobile: '19px',
          ipad_portrait: '20px',
          ipad_landscape: '21px',
          desktop_md: '21px',
          desktop_lg: '21px',
          desktop_xl: '21px'
        },

        xl: { //
          iphone: '21px',
          mobile: '23px',
          ipad_portrait: '25px',
          ipad_landscape: '25px',
          desktop_md: '27px',
          desktop_lg: '32px',
          desktop_xl: '42px'
        },

        '2xl': {
          iphone: '27px',
          mobile: '30px',
          ipad_portrait: '30px',
          ipad_landscape: '30px',
          desktop_md: '30px',
          desktop_lg: '40px',
          desktop_xl: '54px'
        },

        '3xl': { //
          iphone: '36px',
          mobile: '36px',
          ipad_portrait: '41px',
          ipad_landscape: '41px',
          desktop_md: '51px',
          desktop_lg: '57px',
          desktop_xl: '80px'
        },

        '4xl': { //
          iphone: '35px',
          mobile: '40px',
          ipad_portrait: '45px',
          ipad_landscape: '50px',
          desktop_md: '62px',
          desktop_lg: '79px',
          desktop_xl: '90px'
        }
      },

      /* responsive font sizing */
      rfs: {
        minimum: {
          /* minimum values for responsive font sizes.
            max sizes are taken from theme.typography.sizes
            this is per SIZE followed by per BREAKPOINT */
          xs: {
            iphone: {
              'font-size': '12px',
              'line-height': '15px'
            },
            mobile: {
              'font-size': '12px',
              'line-height': '15px'
            },
            ipad_portrait: {
              'font-size': '12px',
              'line-height': '15px'
            },
            ipad_landscape: {
              'font-size': '12px',
              'line-height': '15px'
            },
            desktop_md: {
              'font-size': '14px',
              'line-height': '16px'
            },
            desktop_lg: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_xl: {
              'font-size': '18px',
              'line-height': '24px'
            }
          },

          sm: {
            iphone: {
              'font-size': '14px',
              'line-height': '16px'
            },
            mobile: {
              'font-size': '14px',
              'line-height': '16px'
            },
            ipad_portrait: {
              'font-size': '14px',
              'line-height': '16px'
            },
            ipad_landscape: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_md: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_lg: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_xl: {
              'font-size': '21px',
              'line-height': '27px'
            }
          },

          base: {
            iphone: {
              'font-size': '16px',
              'line-height': '18px'
            },
            mobile: {
              'font-size': '16px',
              'line-height': '18px'
            },
            ipad_portrait: {
              'font-size': '16px',
              'line-height': '18px'
            },
            ipad_landscape: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_md: {
              'font-size': '16px',
              'line-height': '18px'
            },
            desktop_lg: {
              'font-size': '18px',
              'line-height': '24px'
            },
            desktop_xl: {
              'font-size': '24px',
              'line-height': '30px'
            }
          },

          lg: {
            iphone: {
              'font-size': '18px',
              'line-height': '24px'
            },
            mobile: {
              'font-size': '18px',
              'line-height': '24px'
            },
            ipad_portrait: {
              'font-size': '18px',
              'line-height': '24px'
            },
            ipad_landscape: {
              'font-size': '21px',
              'line-height': '28px'
            },
            desktop_md: {
              'font-size': '24px',
              'line-height': '32px'
            },
            desktop_lg: {
              'font-size': '30px',
              'line-height': '42px'
            },
            desktop_xl: {
              'font-size': '38px',
              'line-height': '54px'
            }
          },

          xl: {
            iphone: {
              'font-size': '27px',
              'line-height': '33px'
            },
            mobile: {
              'font-size': '30px',
              'line-height': '36px'
            },
            ipad_portrait: {
              'font-size': '30px',
              'line-height': '36px'
            },
            ipad_landscape: {
              'font-size': '30px',
              'line-height': '36px'
            },
            desktop_md: {
              'font-size': '30px',
              'line-height': '36px'
            },
            desktop_lg: {
              'font-size': '40px',
              'line-height': '46px'
            },
            desktop_xl: {
              'font-size': '54px',
              'line-height': '60px'
            }
          }
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
          'Moderat',
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          '"Helvetica Neue"',
          'Arial',
          'sans-serif'
        ],

        serif: [
          'Freight Text',
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
      '3xs': {
        iphone: '15px',
        mobile: '15px',
        ipad_portrait: '20px',
        ipad_landscape: '20px',
        desktop_md: '20px',
        desktop_lg: '25px',
        desktop_xl: '25px'
      },
      '2xs': {
        iphone: '15px',
        mobile: '15px',
        ipad_portrait: '20px',
        ipad_landscape: '20px',
        desktop_md: '25px',
        desktop_lg: '30px',
        desktop_xl: '40px'
      },
      xs: {
        iphone: '20px',
        mobile: '20px',
        ipad_portrait: '10px',
        ipad_landscape: '15px',
        desktop_md: '20px',
        desktop_lg: '30px',
        desktop_xl: '50px'
      },
      sm: {
        iphone: '25px',
        mobile: '25px',
        ipad_portrait: '25px',
        ipad_landscape: '25px',
        desktop_md: '30px',
        desktop_lg: '40px',
        desktop_xl: '60px'
      },
      md: {
        iphone: '35px',
        mobile: '35px',
        ipad_portrait: '35px',
        ipad_landscape: '45px',
        desktop_md: '55px',
        desktop_lg: '100px',
        desktop_xl: '120px'
      },
      lg: {
        iphone: '50px',
        mobile: '50px',
        ipad_portrait: '50px',
        ipad_landscape: '70px',
        desktop_md: '80px',
        desktop_lg: '130px',
        desktop_xl: '160px'
      },
      xl: {
        iphone: '65px',
        mobile: '65px',
        ipad_portrait: '65px',
        ipad_landscape: '85px',
        desktop_md: '100px',
        desktop_lg: '150px',
        desktop_xl: '180px'
      },
      '2xl': {
        iphone: '140px',
        mobile: '140px',
        ipad_portrait: '120px',
        ipad_landscape: '160px',
        desktop_md: '190px',
        desktop_lg: '250px',
        desktop_xl: '300px'
      }
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
        rows: {
          desktop_md: {
            'grid-row-gap': '40px'
          },
          desktop_lg: {
            'grid-row-gap': '50px'
          },
          desktop_xl: {
            'grid-row-gap': '60px'
          }
        },
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
