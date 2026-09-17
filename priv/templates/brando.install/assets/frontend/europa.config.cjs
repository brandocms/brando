module.exports = {
  setMaxForVw: true,

  /* The width of the design's desktop artboard. Every `dpx` value is relative
     to it: `20dpx` is 20 pixels when the viewport matches this width, and
     scales with the viewport below it. Set it to your Figma frame width. */
  dpxViewportSize: 1440,

  theme: {
    breakpoints: {
      iphone: '0',
      mobile: '480px',
      ipad_portrait: '768px',
      ipad_landscape: '1024px',
      desktop_md: '1280px',
      desktop_lg: '1440px',
      desktop_xl: '1920px',
    },

    breakpointCollections: {
      $mobile: '<=mobile',
      $tablet: 'ipad_portrait/ipad_landscape',
      $desktop: '>=desktop_md',
      $lg: '>=ipad_landscape',
      $sm: '<=ipad_portrait'
    },

    container: {
      /* With `setMaxForVw` the largest breakpoint's maxWidth cannot be a
         percentage — EuropaCSS needs a length to freeze `vw` values against. */
      maxWidth: {
        iphone: '100%',
        mobile: '100%',
        ipad_portrait: '100%',
        ipad_landscape: '100%',
        desktop_md: '100%',
        desktop_lg: '100%',
        desktop_xl: '1920px',
      },

      padding: {
        iphone: '16px',
        mobile: '16px',
        ipad_portrait: '20px',
        ipad_landscape: '20px',
        desktop_md: '20px',
        desktop_lg: '20dpx',
        desktop_xl: '20dpx',
      },
    },

    columns: {
      count: {
        iphone: '12',
        mobile: '12',
        ipad_portrait: '12',
        ipad_landscape: '12',
        desktop_md: '12',
        desktop_lg: '12',
        desktop_xl: '12',
      },

      gutters: {
        iphone: '16px',
        mobile: '16px',
        ipad_portrait: '20px',
        ipad_landscape: '20px',
        desktop_md: '20px',
        desktop_lg: '20dpx',
        desktop_xl: '20dpx',
      },
    },

    colors: {
      transparent: 'transparent',
      white: '#ffffff',
      black: '#000000',
      dark: '#2b2b2b',
      light: '#f9f7f4',

      /* One accent, used for interaction. Change it here and links, hovers and
         highlights follow. */
      accent: '#0f62fe',

      /* Debug helpers: `dbg` for ad-hoc highlighting, `grid` for the column
         overlay EuropaCSS draws. */
      dbg: 'pink',
      grid: 'rgb(0 149 255 / 18%)',

      gray: {
        100: '#f4f4f4',
        300: '#d4d4d4',
        600: '#858585',
        800: '#3d3d3d',
        950: '#1a1a1a'
      },

      body: {
        foreground: '#000000',
        background: '#ffffff'
      },

      link: {
        regular: {
          text: '#000000',
          border: '#000000'
        },
        hover: {
          text: '#000000',
          border: '#000000'
        }
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
    },

    typography: {
      /* `base` is the px value of 1rem set as font-size on the html element. */
      base: '16px',

      /* Fallback line height for inline sizes such as `@fontsize 15px`. Named
         sizes carry their own through `__base__`. */
      lineHeight: {
        iphone: 1.5,
        mobile: 1.5,
        ipad_portrait: 1.5,
        ipad_landscape: 1.5,
        desktop_md: 1.5,
        desktop_lg: 1.5,
        desktop_xl: 1.5,
      },

      /* Sizes are flat pixels up to `desktop_md` and the same number as `dpx`
         above it, so type scales with the artboard on large screens only.

         Line heights are written as `em`, not `%`: browsers floor a percentage
         line height to a whole percent, so `116.667%` lays out as `116%` and
         every fractional pair comes up short. */
      sizes: {
        base: {
          __base__: { 'line-height': '150%' },
          iphone: { 'font-size': '16px' },
          mobile: { 'font-size': '16px' },
          ipad_portrait: { 'font-size': '16px' },
          ipad_landscape: { 'font-size': '16px' },
          desktop_md: { 'font-size': '16px' },
          desktop_lg: { 'font-size': '16dpx' },
          desktop_xl: { 'font-size': '16dpx' },
        },

        'text/xs': {
          __base__: { 'line-height': '150%' },
          iphone: { 'font-size': '12px' },
          mobile: { 'font-size': '12px' },
          ipad_portrait: { 'font-size': '12px' },
          ipad_landscape: { 'font-size': '12px' },
          desktop_md: { 'font-size': '12px' },
          desktop_lg: { 'font-size': '12dpx' },
          desktop_xl: { 'font-size': '12dpx' },
        },

        'text/sm': {
          __base__: { 'line-height': '1.42858em' },
          iphone: { 'font-size': '14px' },
          mobile: { 'font-size': '14px' },
          ipad_portrait: { 'font-size': '14px' },
          ipad_landscape: { 'font-size': '14px' },
          desktop_md: { 'font-size': '14px' },
          desktop_lg: { 'font-size': '14dpx' },
          desktop_xl: { 'font-size': '14dpx' },
        },

        'text/base': {
          __base__: { 'line-height': '150%' },
          iphone: { 'font-size': '16px' },
          mobile: { 'font-size': '16px' },
          ipad_portrait: { 'font-size': '16px' },
          ipad_landscape: { 'font-size': '16px' },
          desktop_md: { 'font-size': '16px' },
          desktop_lg: { 'font-size': '16dpx' },
          desktop_xl: { 'font-size': '16dpx' },
        },

        'text/lg': {
          __base__: { 'line-height': '1.44445em' },
          iphone: { 'font-size': '18px' },
          mobile: { 'font-size': '18px' },
          ipad_portrait: { 'font-size': '18px' },
          ipad_landscape: { 'font-size': '18px' },
          desktop_md: { 'font-size': '18px' },
          desktop_lg: { 'font-size': '18dpx' },
          desktop_xl: { 'font-size': '18dpx' },
        },

        'heading/xl': {
          __base__: { 'line-height': '140%' },
          iphone: { 'font-size': '20px' },
          mobile: { 'font-size': '20px' },
          ipad_portrait: { 'font-size': '20px' },
          ipad_landscape: { 'font-size': '20px' },
          desktop_md: { 'font-size': '20px' },
          desktop_lg: { 'font-size': '20dpx' },
          desktop_xl: { 'font-size': '20dpx' },
        },

        'heading/2xl': {
          __base__: { 'line-height': '1.33334em' },
          iphone: { 'font-size': '24px' },
          mobile: { 'font-size': '24px' },
          ipad_portrait: { 'font-size': '24px' },
          ipad_landscape: { 'font-size': '24px' },
          desktop_md: { 'font-size': '24px' },
          desktop_lg: { 'font-size': '24dpx' },
          desktop_xl: { 'font-size': '24dpx' },
        },

        'heading/3xl': {
          __base__: { 'line-height': '1.26667em' },
          iphone: { 'font-size': '30px' },
          mobile: { 'font-size': '30px' },
          ipad_portrait: { 'font-size': '30px' },
          ipad_landscape: { 'font-size': '30px' },
          desktop_md: { 'font-size': '30px' },
          desktop_lg: { 'font-size': '30dpx' },
          desktop_xl: { 'font-size': '30dpx' },
        },

        'heading/4xl': {
          __base__: { 'line-height': '1.33334em' },
          iphone: { 'font-size': '36px' },
          mobile: { 'font-size': '36px' },
          ipad_portrait: { 'font-size': '36px' },
          ipad_landscape: { 'font-size': '36px' },
          desktop_md: { 'font-size': '36px' },
          desktop_lg: { 'font-size': '36dpx' },
          desktop_xl: { 'font-size': '36dpx' },
        },

        'heading/5xl': {
          __base__: { 'line-height': '1.16667em' },
          iphone: { 'font-size': '48px' },
          mobile: { 'font-size': '48px' },
          ipad_portrait: { 'font-size': '48px' },
          ipad_landscape: { 'font-size': '48px' },
          desktop_md: { 'font-size': '48px' },
          desktop_lg: { 'font-size': '48dpx' },
          desktop_xl: { 'font-size': '48dpx' },
        },

        'heading/6xl': {
          __base__: { 'line-height': '1.13334em' },
          iphone: { 'font-size': '60px' },
          mobile: { 'font-size': '60px' },
          ipad_portrait: { 'font-size': '60px' },
          ipad_landscape: { 'font-size': '60px' },
          desktop_md: { 'font-size': '60px' },
          desktop_lg: { 'font-size': '60dpx' },
          desktop_xl: { 'font-size': '60dpx' },
        },
      },

      families: {
        /* `main` is what `@europa base` sets on the body. */
        main: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          '"Helvetica Neue"',
          'Arial',
          'sans-serif'
        ],

        sans: [
          '-apple-system',
          'BlinkMacSystemFont',
          '"Segoe UI"',
          'Roboto',
          '"Helvetica Neue"',
          'Arial',
          'sans-serif'
        ],

        serif: ['Georgia', 'Cambria', '"Times New Roman"', 'Times', 'serif'],

        mono: ['Menlo', 'Monaco', 'Consolas', '"Liberation Mono"', '"Courier New"', 'monospace']
      }
    },

    /* Spacing steps are flat across breakpoints: a component picks a smaller
       step on mobile rather than the step shrinking. Only the block rhythm,
       the container and the gutters change size. Keep this map flat — nesting
       steps under `padding:`/`gap:` keys makes every lookup return NaN. */
    spacing: {
      xxxs: {
        iphone: '4px',
        mobile: '4px',
        ipad_portrait: '4px',
        ipad_landscape: '4px',
        desktop_md: '4px',
        desktop_lg: '4dpx',
        desktop_xl: '4dpx',
      },

      xxs: {
        iphone: '8px',
        mobile: '8px',
        ipad_portrait: '8px',
        ipad_landscape: '8px',
        desktop_md: '8px',
        desktop_lg: '8dpx',
        desktop_xl: '8dpx',
      },

      xs: {
        iphone: '10px',
        mobile: '10px',
        ipad_portrait: '10px',
        ipad_landscape: '10px',
        desktop_md: '10px',
        desktop_lg: '10dpx',
        desktop_xl: '10dpx',
      },

      sm: {
        iphone: '16px',
        mobile: '16px',
        ipad_portrait: '16px',
        ipad_landscape: '16px',
        desktop_md: '16px',
        desktop_lg: '16dpx',
        desktop_xl: '16dpx',
      },

      md: {
        iphone: '24px',
        mobile: '24px',
        ipad_portrait: '24px',
        ipad_landscape: '24px',
        desktop_md: '24px',
        desktop_lg: '24dpx',
        desktop_xl: '24dpx',
      },

      lg: {
        iphone: '40px',
        mobile: '40px',
        ipad_portrait: '40px',
        ipad_landscape: '40px',
        desktop_md: '40px',
        desktop_lg: '40dpx',
        desktop_xl: '40dpx',
      },

      xl: {
        iphone: '48px',
        mobile: '48px',
        ipad_portrait: '64px',
        ipad_landscape: '80px',
        desktop_md: '80px',
        desktop_lg: '80dpx',
        desktop_xl: '80dpx',
      },

      xxl: {
        iphone: '128px',
        mobile: '128px',
        ipad_portrait: '128px',
        ipad_landscape: '128px',
        desktop_md: '128px',
        desktop_lg: '128dpx',
        desktop_xl: '128dpx',
      },

      blocks: {
        iphone: '128px',
        mobile: '128px',
        ipad_portrait: '128px',
        ipad_landscape: '160px',
        desktop_md: '160px',
        desktop_lg: '160dpx',
        desktop_xl: '160dpx',
      },

      blocksInner: {
        iphone: '64px',
        mobile: '64px',
        ipad_portrait: '64px',
        ipad_landscape: '80px',
        desktop_md: '80px',
        desktop_lg: '80dpx',
        desktop_xl: '80dpx',
      },

      indent: {
        iphone: '0px',
        mobile: '0px',
        ipad_portrait: '0px',
        ipad_landscape: '48px',
        desktop_md: '48px',
        desktop_lg: '48dpx',
        desktop_xl: '48dpx',
      },

      radius: {
        regular: {
          iphone: '4px',
          mobile: '4px',
          ipad_portrait: '4px',
          ipad_landscape: '4px',
          desktop_md: '4px',
          desktop_lg: '4dpx',
          desktop_xl: '4dpx',
        },

        image: {
          iphone: '8px',
          mobile: '8px',
          ipad_portrait: '8px',
          ipad_landscape: '8px',
          desktop_md: '8px',
          desktop_lg: '8dpx',
          desktop_xl: '8dpx',
        },
      },
    }
  }
}
