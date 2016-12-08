import $ from 'jquery';

class ImagePreview {
  static setup() {
    $('.grid-form input[type=file]')
      .on('change', (e) => {
        ImagePreview.previewImage(e.target, [150], 5);
      });
  }

  static previewImage(el, widths, limit) {
    let output;
    const files = el.files;
    const wrap = el.parentNode;
    const imagePreviews = wrap.getElementsByClassName('image-preview');

    if (imagePreviews.length > 0) {
      output = wrap.getElementsByClassName('image-preview')[0];
    } else {
      output = document.createElement('div');
      output.className = 'image-preview';
      wrap.insertBefore(output, wrap.firstChild.nextSibling);
    }

    const imageTypes = ['JPG', 'JPEG', 'GIF', 'PNG'];

    const file = files[0];
    const imageType = /image.*/;

    // detect device
    const device = ImagePreview.detectDevice();

    if (!device.android) {
      // Since android doesn't handle file types right,
      // do not do this check for phones
      if (!file.type.match(imageType)) {
        return false;
      }
    }

    const img = '';

    const reader = new FileReader();
    reader.onload = (function onLoad() {
      return (e) => {
        output.innerHTML = '';

        let format = e.target.result.split(';');
        format = format[0].split('/');
        format = format[1].split('+');
        format = format[0].toUpperCase();

        // We will change this for an android
        if (device.android) {
          format = file.name.split('.');
          format = format[format.length - 1].split('+');
          format = format[0].toUpperCase();
        }

        const description = document.createElement('p');
        description.innerHTML = `
          <span class="text-mono" style="font-size: 12px;">
            <b>${format}</b>/<b>${(e.total / 1024).toFixed(2)}</b> KB.
          </span>
        `;

        if (imageTypes.indexOf(format) >= 0 && e.total < (limit * 1024 * 1024)) {
          for (const size in widths) {
            if ({}.hasOwnProperty.call(widths, size)) {
              const image = document.createElement('img');
              const src = e.target.result;

              image.src = src;

              image.width = widths[size];
              image.title = `${widths[size]}px`;
              output.appendChild(image);
            }
          }
        }
        output.appendChild(description);
      };
    }(img));

    reader.readAsDataURL(file);
    return true;
  }

  // Detect client's device
  static detectDevice() {
    const ua = navigator.userAgent;
    const brand = {
      apple: ua.match(/(iPhone|iPod|iPad)/),
      blackberry: ua.match(/BlackBerry/),
      android: ua.match(/Android/),
      microsoft: ua.match(/Windows Phone/),
      zune: ua.match(/ZuneWP7/),
    };

    return brand;
  }
}

export default ImagePreview;
