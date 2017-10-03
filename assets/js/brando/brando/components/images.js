import $ from 'jquery';
import Dropzone from 'dropzone';

import accordion from './accordion';
import Utils from './utils';
import vex from './vex_brando';
import i18n from './i18n';

let imagePool = [];

class Images {
  static setup() {
    Images.getHash();
    Images.deleteListener();
    Images.imageSelectionListener();
    Images.imagePropertiesListener();
  }

  static getHash() {
    let hash = document.location.hash;
    if (hash) {
      hash = `#tab-${hash.slice(1)}`;
    } else {
      // get the first tab as hash
      hash = `#${$('.tab-link').first().attr('id')}`;
    }
    accordion.activateTab(hash);
  }

  static imageSelectionListener() {
    $('.image-selection-pool img')
      .click(function onClick() {
        if ($(this)
          .hasClass('selected')) {
          // remove from selected pool
          let pos;
          for (let i = 0; i < imagePool.length; i += 1) {
            if (imagePool[i] === $(this).attr('data-id')) {
              pos = i;
              break;
            }
          }
          imagePool.splice(pos, 1);
        } else {
          // add to selected pool
          if (!imagePool) {
            imagePool = [];
          }
          imagePool.push($(this).attr('data-id'));
        }
        $(this).toggleClass('selected');
        Images.checkButtonEnable(this);
      });
  }

  static imagePropertiesListener() {
    $(document)
      .on({
        mouseenter: function onMouseEnter() {
          $(this)
            .find('.overlay')
            .css('visibility', 'visible');
        },
        mouseleave: function onMouseLeave() {
          $(this)
            .find('.overlay')
            .css('visibility', 'hidden');
        },
      }, '.image-wrapper');

    $(document)
      .on('click', '.edit-properties', function onClick(e) {
        e.preventDefault();

        let attrs;
        const $content = $('<div>');
        const $img = $(this).parent()
                          .parent()
                          .find('img')
                          .clone();

        let todayDateString = new Date().toJSON().slice(0, 10)
        vex.dialog.open({
            message: '',
            input: [`
              ${$img[0].outerHTML}
              ${Images.buildAttrs($img.data())}
            `].join(''),
            callback: function dialogCallback(form) {
              const formWithoutId = form;
              if (form !== false) {
                const id = formWithoutId.id;
                delete formWithoutId.id;
                const data = {
                  form: formWithoutId,
                  id: id,
                };
                Images.submitProperties(data);
              }
            },
          });

      });
  }

  static submitProperties(submitData) {
    $.ajax({
      headers: {
        Accept: 'application/json; charset=utf-8',
      },
      type: 'POST',
      data: submitData,
      url: Utils.addToPathName('set-properties'),
    })
    .done($.proxy((data) => {
      /**
       * Callback after confirming.
       */
      if (data.status === '200') {
        // success
        const $img = $(`.image-serie img[data-id=${data.id}]`);
        $.each(data.attrs, (attr, val) => {
          $img.attr(`data-${attr}`, val);
        });
      } else {
        vex.dialog.alert(data.error_msg);
      }
    }));
  }

  static buildAttrs(data) {
    let ret = '';
    $.each(data, (attr, val) => {
      if (attr === 'id') {
        ret += `<input name="id" type="hidden" value="${val}" />`;
      } else {
        ret += `
          <div><label>${Images.capitalize(attr)}</label>
          <input name="${attr}" type="text" value="${val}" /></div>
        `;
      }
    });
    return ret;
  }

  static capitalize(word) {
    return $.camelCase(`-${word}`);
  }

  static checkButtonEnable(scope) {
    const $scope = $(scope).parent()
                           .parent();
    const $btn = $('.delete-selected-images', $scope);

    if (imagePool.length > 0) {
      $btn.removeAttr('disabled');
    } else {
      $btn.attr('disabled', 'disabled');
    }
  }

  static deleteListener() {
    $('.delete-selected-images')
      .click((e) => {
        e.preventDefault();
        vex.dialog.confirm({
          message: i18n.t('images:delete_confirm'),
          callback: function dialogCallback(value) {
            if (value) {
              $(this)
                .removeClass('btn-danger')
                .addClass('btn-warning')
                .html(i18n.t('images:deleting'));
              $.ajax({
                headers: {
                  Accept: 'application/json; charset=utf-8',
                },
                type: 'POST',
                url: Utils.addToPathName('delete-selected-images'),
                data: {
                  ids: imagePool,
                },
                success: Images.deleteSuccess,
              });
            }
          },
        });
      });
  }

  static deleteSuccess(data) {
    if (data.status === '200') {
      $('.delete-selected-images')
        .removeClass('btn-warning')
        .addClass('btn-danger')
        .html(i18n.t('images:delete_images'))
        .attr('disabled', 'disabled');

      for (let i = 0; i < data.ids.length; i += 1) {
        const imgSel = `.image-selection-pool img[data-id=${data.ids[i]}]`;
        $(imgSel).fadeOut(() => {
          $(imgSel).parent().remove();
        });
      }
      imagePool = [];
    }
  }

  static setupUpload() {
    const dz = new Dropzone('#brando-dropzone', {
      paramName: 'image',
      maxFilesize: 10,
      thumbnailHeight: 150,
      thumbnailWidth: 150,
    });

    $(`<div class="dz-default dz-message">
        <span>
          <i class="fa fa-cloud fa-4x"></i><br>
          Klikk her eller dra og slipp bilder her for å laste opp
        </span>
      </div>
    `).appendTo('#brando-dropzone');

    return dz;
  }
}

export default Images;
