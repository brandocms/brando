import $ from 'jquery';

import Accordion from './accordion';
import Utils from './utils';
import { vex } from './vex_brando';
import bI18n from './i18n';

let imagePool = [];

class Images {
  static setup() {
    this.getHash();
    this.deleteListener();
    this.imageSelectionListener();
    this.imagePropertiesListener();
  }
  static getHash() {
    const hash = document.location.hash;
    if (hash) {
      Accordion.activateTab(`#tab-${hash.slice(1)}`);
    }
  }
  static imageSelectionListener() {
    const that = this;
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
        that.checkButtonEnable(this);
      });
  }

  static imagePropertiesListener() {
    const that = this;

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

        vex.dialog.open({
          message: '',
          input: function inputCallback() {
            attrs = that.buildAttrs($img.data());
            $content.append($img)
                    .append(attrs);

            return $content;
          },
          callback: function dialogCallback(form) {
            const formWithoutId = form;
            if (form !== false) {
              const id = formWithoutId.id;
              delete formWithoutId.id;
              const data = {
                form: formWithoutId,
                id: id,
              };
              that.submitProperties(data);
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
      }
    }));
  }

  static buildAttrs(data) {
    const that = this;
    let ret = '';
    $.each(data, (attr, val) => {
      if (attr === 'id') {
        ret += `<input name="id" type="hidden" value="${val}" />`;
      } else {
        ret += `
          <div><label>${that.capitalize(attr)}</label>
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
    const that = this;
    $('.delete-selected-images')
      .click((e) => {
        e.preventDefault();
        vex.dialog.confirm({
          message: bI18n.t('images:delete_confirm'),
          callback: function dialogCallback(value) {
            if (value) {
              $(this)
                .removeClass('btn-danger')
                .addClass('btn-warning')
                .html(bI18n.t('images:deleting'));
              $.ajax({
                headers: {
                  Accept: 'application/json; charset=utf-8',
                },
                type: 'POST',
                url: Utils.addToPathName('delete-selected-images'),
                data: {
                  ids: imagePool,
                },
                success: that.deleteSuccess,
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
        .html(bI18n.t('images:delete_images'))
        .attr('disabled', 'disabled');

      for (let i = 0; i < data.ids.length; i += 1) {
        $(`.image-selection-pool img[data-id=${data.ids[i]}]`).fadeOut();
      }
      imagePool = [];
    }
  }
}

export default Images;
