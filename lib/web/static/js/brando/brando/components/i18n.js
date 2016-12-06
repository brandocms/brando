import i18next from 'i18next';

export default i18next.init({
  lng: this.language,
  fallbackLng: 'nb',
  resources: {
    en: {
      image_config: {
        key: 'key',
        masterkey: 'masterkey',
        orientation_landscape: 'orientation / landscape',
        orientation_portrait: 'orientation / portrait',
        value: 'value',
      },
      images: {
        delete_confirm: 'Are you sure you want to delete these images?',
        delete_images: 'Delete images',
        deleting: 'Deleting...',
      },
      sequence: {
        store_new: 'Store new sequence',
        stored: 'Sequence stored!',
        storing: 'Storing...',
      },
      translation: {
        key: 'hello world',
      },
      vex: {
        cancel: 'Cancel',
      },
      ws: {
        working: 'Working... Please wait',
      },
    },
    nb: {
      image_config: {
        key: 'nøkkel',
        masterkey: 'hovednøkkel',
        orientation_landscape: 'bildeformat / liggende',
        orientation_portrait: 'bildeformat / stående',
        value: 'verdi',
      },
      images: {
        delete_confirm: 'Er du sikker på at du vil slette disse bildene?',
        delete_images: 'Slett bilder',
        deleting: 'Sletter',
      },
      sequence: {
        store_new: 'Lagre ny rekkefølge',
        stored: 'Rekkefølge lagret!',
        storing: 'Lagrer...',
      },
      vex: {
        cancel: 'Angre',
      },
      ws: {
        working: 'Jobber... Vennligst vent',
      },
    },
  },
});
