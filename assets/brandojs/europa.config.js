module.exports = {
  theme: {
    breakpoints: {
      iphone: '0',
      mobile: '480px',
      ipad_portrait: '768px',
      ipad_landscape: '1024px',
      desktop_md: '1200px',
      desktop_lg: '1530px',
      desktop_xl: '1920px'
    },

    colors: () => ({
      dark: '#000080',
      input: '#FAEFEA',
      peach: '#FCF5F3',
      peachLighter: '#fffbfa',
      peachDarker: '#F6DFD5',
      peachDarkest: '#ECBFAC',
      blue: '#0047FF',
      overlay: '#363E5C'
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
        ipad_portrait: '50px',
        ipad_landscape: '50px',
        desktop_md: '50px',
        desktop_lg: '50px',
        desktop_xl: '50px'
      }
    },

    columns: {
      count: {
        iphone: 2,
        mobile: 2,
        ipad_portrait: 16,
        ipad_landscape: 16,
        desktop_md: 16,
        desktop_lg: 16,
        desktop_xl: 16
      },
      gutters: {
        iphone: '40px',
        mobile: '40px',
        ipad_portrait: '35px',
        ipad_landscape: '35px',
        desktop_md: '30px',
        desktop_lg: '30px',
        desktop_xl: '15px'
      }
    },

    typography: {
      /* `base` is the px value of 1rem set as font-size on the html element. */
      base: '20px',

      /* line heights per breakpoint */
      lineHeight: {
        iphone: 1.35,
        mobile: 1.35,
        ipad_portrait: 1.35,
        ipad_landscape: 1.35,
        desktop_md: 1.35,
        desktop_lg: 1.35,
        desktop_xl: 1.35
      },

      /* paddingDivider is used to set column-typography right padding.
         Lower values = more padding */
      paddingDivider: 8,

      /* main font sizing map */
      sizes: {
        'nav.section': {
          iphone: {
            'font-size': '18px',
            'line-height': '140%'
          },
          mobile: {
            'font-size': '18px',
            'line-height': '140%'
          },
          ipad_portrait: {
            'font-size': '18px',
            'line-height': '140%'
          },
          ipad_landscape: {
            'font-size': '18px',
            'line-height': '140%'
          },
          desktop_md: {
            'font-size': '18px',
            'line-height': '140%'
          },
          desktop_lg: {
            'font-size': '18px',
            'line-height': '140%'
          },
          desktop_xl: {
            'font-size': '18px',
            'line-height': '140%'
          }
        },

        'nav.mainItem': {
          iphone: {
            'font-size': '28px',
            'line-height': '40px'
          },
          mobile: {
            'font-size': '28px',
            'line-height': '40px'
          },
          ipad_portrait: {
            'font-size': '28px',
            'line-height': '40px'
          },
          ipad_landscape: {
            'font-size': '28px',
            'line-height': '40px'
          },
          desktop_md: {
            'font-size': '28px',
            'line-height': '40px'
          },
          desktop_lg: {
            'font-size': '28px',
            'line-height': '40px'
          },
          desktop_xl: {
            'font-size': '28px',
            'line-height': '40px'
          }
        },

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
          iphone: '16px',
          mobile: '16px',
          ipad_portrait: '16px',
          ipad_landscape: '16px',
          desktop_md: '16px',
          desktop_lg: '16px',
          desktop_xl: '16px'
        },

        base: {
          iphone: '20px',
          mobile: '20px',
          ipad_portrait: '20px',
          ipad_landscape: '20px',
          desktop_md: '20px',
          desktop_lg: '20px',
          desktop_xl: '20px'
        },

        lg: {
          iphone: {
            'font-size': '24px'
          },
          mobile: {
            'font-size': '24px'
          },
          ipad_portrait: {
            'font-size': '24px'
          },
          ipad_landscape: {
            'font-size': '24px'
          },
          desktop_md: {
            'font-size': '24px'
          },
          desktop_lg: {
            'font-size': '24px'
          },
          desktop_xl: {
            'font-size': '24px'
          }
        },

        xl: { //
          iphone: {
            'font-size': '40px',
            'font-weight': '200'
          },
          mobile: {
            'font-size': '40px',
            'font-weight': '200'
          },
          ipad_portrait: {
            'font-size': '40px',
            'font-weight': '200'
          },
          ipad_landscape: {
            'font-size': '40px',
            'font-weight': '200'
          },
          desktop_md: {
            'font-size': '40px',
            'font-weight': '200'
          },
          desktop_lg: {
            'font-size': '40px',
            'font-weight': '200'
          },
          desktop_xl: {
            'font-size': '40px',
            'font-weight': '200'
          }
        },

        '2xl': {
          iphone: '27px',
          mobile: '30px',
          ipad_portrait: '30px',
          ipad_landscape: '30px',
          desktop_md: '40px',
          desktop_lg: '48px',
          desktop_xl: '64px'
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
          iphone: {
            'font-size': '55px',
            'line-height': '1'
          },
          mobile: {
            'font-size': '55px',
            'line-height': '1'
          },

          desktop_md: {
            'font-size': '55px',
            'line-height': '1'
          },

          desktop_lg: {
            'font-size': '55px',
            'line-height': '1'
          },

          desktop_xl: {
            'font-size': '55px',
            'line-height': '1'
          }
        }
      },

      families: {
        main: [
          'Founders Grotesk',
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
          'Maison Neue',
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
        iphone: '15px',
        mobile: '15px',
        ipad_portrait: '15px',
        ipad_landscape: '15px',
        desktop_md: '15px',
        desktop_lg: '15px',
        desktop_xl: '15px'
      },
      sm: {
        iphone: '25px',
        mobile: '25px',
        ipad_portrait: '25px',
        ipad_landscape: '25px',
        desktop_md: '25px',
        desktop_lg: '25px',
        desktop_xl: '25px'
      },
      md: {
        iphone: '50px',
        mobile: '50px',
        ipad_portrait: '50px',
        ipad_landscape: '50px',
        desktop_md: '50px',
        desktop_lg: '50px',
        desktop_xl: '50px'
      },
      lg: {
        iphone: '100px',
        mobile: '100px',
        ipad_portrait: '100px',
        ipad_landscape: '100px',
        desktop_md: '100px',
        desktop_lg: '100px',
        desktop_xl: '100px'
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
    }
  }
}
