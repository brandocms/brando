export default {
  en: [
    {
      name: 'Text',
      icon: 'fa-paragraph',
      component: 'Text',
      dataTemplate: {
        text: '',
        type: 'paragraph',
        extensions: []
      }
    },

    {
      name: 'Heading',
      icon: 'fa-heading',
      component: 'Header',
      dataTemplate: {
        text: 'Heading',
        level: 1,
        class: null,
        id: null
      }
    },

    {
      name: 'Divider',
      icon: 'fa-minus',
      component: 'Divider',
      dataTemplate: {
        text: '-------------'
      }
    },

    {
      name: 'List',
      icon: 'fa-list',
      component: 'List',
      dataTemplate: {
        id: null,
        class: null,
        rows: []
      }
    },

    {
      name: 'Media',
      icon: 'fa-photo-video',
      component: 'Media',
      dataTemplate: {
        type: null,
        available_components: [
          { component: 'Picture', dataTemplate: {} },
          { component: 'Video', dataTemplate: {} },
          { component: 'Slideshow', dataTemplate: {} },
          { component: 'Gallery', dataTemplate: {} },
          { component: 'Svg', dataTemplate: {} }
        ],
        data: null
      }
    },

    {
      name: 'Image — legacy',
      icon: 'fa-image',
      component: 'Image',
      hide: true,
      dataTemplate: {
        url: '',
        sizes: null,
        title: '',
        credits: '',
        alt: '',
        class: 'img-fluid',
        series_slug: 'post'
      }
    },

    {
      name: 'Slider',
      icon: 'fa-images',
      component: 'Slideshow',
      dataTemplate: {
        images: [],
        class: '',
        series_slug: 'post',
        lightbox: false
      }
    },

    {
      name: 'Gallery',
      icon: 'fa-images',
      component: 'Gallery',
      dataTemplate: {
        images: [],
        class: '',
        series_slug: 'post',
        lightbox: false,
        placeholder: 'dominant_color'
      }
    },

    {
      name: 'Picture',
      icon: 'fa-portrait',
      component: 'Picture',
      dataTemplate: {
        url: '',
        sizes: null,
        title: '',
        credits: '',
        alt: '',
        link: null,
        img_class: 'img-fluid',
        picture_class: '',
        srcset: '',
        media_queries: '',
        series_slug: 'post'
      }
    },

    {
      name: 'Video',
      icon: 'fa-video',
      component: 'Video',
      dataTemplate: {
        source: 'youtube',
        remote_id: '',
        poster: null,
        width: null,
        height: null
      }
    },

    {
      name: 'Input',
      icon: 'fa-keyboard',
      component: 'Input',
      dataTemplate: {
        type: 'input',
        label: 'label',
        placeholder: 'placeholder',
        help_text: null,
        value: null
      }
    },

    {
      name: 'Datasource',
      icon: 'fa-database',
      component: 'Datasource',
      dataTemplate: {
        module: null,
        type: null,
        query: null,
        code: null,
        arg: null,
        limit: null,
        ids: [],
        description: null,
        module_id: null
      }
    },

    {
      name: 'Svg',
      icon: 'fa-code',
      component: 'Svg',
      dataTemplate: {
        code: '',
        class: ''
      }
    },

    {
      name: 'Data table',
      icon: 'fa-table',
      component: 'Datatable',
      dataTemplate: {
        rows: [],
        class: ''
      }
    },

    {
      name: 'Map',
      icon: 'fa-compass',
      component: 'Map',
      dataTemplate: {
        source: 'gmaps',
        embed_url: ''
      }
    },

    {
      name: 'Quote',
      icon: 'fa-quote-right',
      component: 'Blockquote',
      dataTemplate: {
        text: 'Quote',
        cite: 'Quote author'
      }
    },

    {
      name: 'Timeline',
      icon: 'fa-clock',
      component: 'Timeline',
      dataTemplate: {
        rows: [
          {
            caption: '2022',
            text: 'Description'
          }
        ]
      }
    },

    {
      name: 'Columns',
      icon: 'fa-columns',
      component: 'Columns',
      dataTemplate: []
    },

    {
      name: 'Container',
      icon: 'fa-square',
      component: 'Container',
      dataTemplate: {
        class: 'standard',
        description: '',
        blocks: [],
        wrapper: ''
      }
    },

    {
      name: 'Markdown',
      icon: 'fa-code',
      component: 'Markdown',
      dataTemplate: {
        text: '## Markdown code'
      }
    },

    {
      name: 'Html',
      icon: 'fa-file-code',
      component: 'Html',
      dataTemplate: {
        text: 'html'
      }
    },

    {
      name: 'Comment (hidden)',
      icon: 'fa-comment',
      component: 'Comment',
      dataTemplate: {
        text: 'Comment...'
      }
    }
  ],
  no: [
    {
      name: 'Tekst',
      icon: 'fa-paragraph',
      component: 'Text',
      dataTemplate: {
        text: '',
        type: 'paragraph',
        extensions: []
      }
    },

    {
      name: 'Overskrift',
      icon: 'fa-heading',
      component: 'Header',
      dataTemplate: {
        text: 'Overskrift',
        level: 1,
        class: null,
        id: null
      }
    },

    {
      name: 'Skillelinje',
      icon: 'fa-minus',
      component: 'Divider',
      dataTemplate: {
        text: '-------------'
      }
    },

    {
      name: 'Liste',
      icon: 'fa-list',
      component: 'List',
      dataTemplate: {
        id: null,
        class: null,
        rows: []
      }
    },

    {
      name: 'Media',
      icon: 'fa-photo-video',
      component: 'Media',
      dataTemplate: {
        type: null,
        available_components: [
          { component: 'Picture', dataTemplate: {} },
          { component: 'Video', dataTemplate: {} },
          { component: 'Gallery', dataTemplate: {} },
          { component: 'Slideshow', dataTemplate: {} },
          { component: 'Svg', dataTemplate: {} }
        ],
        data: null
      }
    },

    {
      name: 'Bilde — legacy',
      icon: 'fa-image',
      component: 'Image',
      hide: true,
      dataTemplate: {
        url: '',
        sizes: null,
        title: '',
        credits: '',
        alt: '',
        class: 'img-fluid',
        series_slug: 'post'
      }
    },

    {
      name: 'Slider',
      icon: 'fa-images',
      component: 'Slideshow',
      dataTemplate: {
        images: [],
        class: '',
        series_slug: 'post',
        lightbox: false
      }
    },

    {
      name: 'Galleri',
      icon: 'fa-images',
      component: 'Gallery',
      dataTemplate: {
        images: [],
        class: '',
        series_slug: 'post',
        lightbox: false,
        placeholder: 'dominant_color'
      }
    },

    {
      name: 'Bilde',
      icon: 'fa-portrait',
      component: 'Picture',
      dataTemplate: {
        url: '',
        sizes: null,
        title: '',
        credits: '',
        alt: '',
        link: null,
        img_class: 'img-fluid',
        picture_class: '',
        srcset: '',
        media_queries: '',
        lightbox: false,
        series_slug: 'post',
        webp: false
      }
    },

    {
      name: 'Video',
      icon: 'fa-video',
      component: 'Video',
      dataTemplate: {
        source: 'youtube',
        remote_id: '',
        poster: null,
        width: null,
        height: null
      }
    },

    {
      name: 'Input',
      icon: 'fa-keyboard',
      component: 'Input',
      dataTemplate: {
        type: 'input',
        label: 'label',
        placeholder: 'placeholder',
        help_text: null,
        value: null
      }
    },

    {
      name: 'Datakilde',
      icon: 'fa-database',
      component: 'Datasource',
      dataTemplate: {
        module: null,
        type: null,
        query: null,
        code: null,
        arg: null,
        limit: null,
        ids: [],
        description: null,
        module_id: null
      }
    },

    {
      name: 'Svg',
      icon: 'fa-code',
      component: 'Svg',
      dataTemplate: {
        code: '',
        class: ''
      }
    },

    {
      name: 'Datatabell',
      icon: 'fa-table',
      component: 'Datatable',
      dataTemplate: {
        rows: [],
        class: ''
      }
    },

    {
      name: 'Kart',
      icon: 'fa-compass',
      component: 'Map',
      dataTemplate: {
        source: 'gmaps',
        embed_url: ''
      }
    },

    {
      name: 'Sitat',
      icon: 'fa-quote-right',
      component: 'Blockquote',
      dataTemplate: {
        text: 'Sitat',
        cite: 'Sitatforfatter'
      }
    },

    {
      name: 'Tidslinje',
      icon: 'fa-clock',
      component: 'Timeline',
      dataTemplate: {
        rows: [
          {
            caption: '2022',
            text: 'Tekst om hendelsen'
          }
        ]
      }
    },

    {
      name: 'Kolonner',
      icon: 'fa-columns',
      component: 'Columns',
      dataTemplate: []
    },

    {
      name: 'Seksjon',
      icon: 'fa-square',
      component: 'Container',
      dataTemplate: {
        class: 'standard',
        description: '',
        blocks: [],
        wrapper: ''
      }
    },

    {
      name: 'Markdown',
      icon: 'fa-code',
      component: 'Markdown',
      dataTemplate: {
        text: '## Markdown code'
      }
    },

    {
      name: 'Html',
      icon: 'fa-file-code',
      component: 'Html',
      dataTemplate: {
        text: 'html'
      }
    },

    {
      name: 'Kommentar (vises ikke)',
      icon: 'fa-comment',
      component: 'Comment',
      dataTemplate: {
        text: 'Kommentar...'
      }
    }
  ]
}
