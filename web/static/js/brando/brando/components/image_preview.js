"use strict";

import $ from "jquery";

class ImagePreview {
    static setup() {
        console.log("SETUP")
        $('.grid-form input[type=file]').on('change', function(e) {
            ImagePreview.previewImage(e.target, [150], 5);
        });
    }

    static previewImage(el, widths, limit){
    	var files = el.files;
    	var wrap = el.parentNode;
        var imagePreviews = wrap.getElementsByClassName('image-preview');
        if (imagePreviews.length > 0) {
            var output = wrap.getElementsByClassName('image-preview')[0];
        } else {
            var output = document.createElement('div');
            output.className = 'image-preview';
            wrap.insertBefore(output, wrap.firstChild.nextSibling);
        }

    	var imageTypes = ['JPG','JPEG','GIF','PNG'];

    	var file = files[0];
    	var imageType = /image.*/;

    	// detect device
    	var device = ImagePreview.detectDevice();

    	if (!device.android) { // Since android doesn't handle file types right, do not do this check for phones
    		if (!file.type.match(imageType)) {
    			return false;
    		}
    	}

    	var img='';

    	var reader = new FileReader();
    	reader.onload = (function(aImg) {
    		return function(e) {
    			output.innerHTML='';

    			var format = e.target.result.split(';');
    			format = format[0].split('/');
        		format = format[1].split('+');
    			format = format[0].toUpperCase();

    			// We will change this for an android
    			if (device.android) {
    				format = file.name.split('.');
            		format = format[format.length-1].split('+');
    				format = format[0].toUpperCase();
    			}

    			var description = document.createElement('p');
    			description.innerHTML = `<span class="text-mono" style="font-size: 12px;"><b>${format}</b>/<b>${(e.total/1024).toFixed(2)}</b> KB.</span>`;

    			if (imageTypes.indexOf(format) >= 0 && e.total < (limit*1024*1024)) {
    				for (var size in widths) {
    					var image = document.createElement('img');
    					var src = e.target.result;

    					image.src = src;

    					image.width = widths[size];
    					image.title = `${widths[size]}px`;
    					output.appendChild(image);
    				}
    			}
    			output.appendChild(description);
    		};
    	})(img);
    	reader.readAsDataURL(file);
    }

    // Detect client's device
    static detectDevice(){
    	var ua = navigator.userAgent;
    	var brand = {
    		apple: ua.match(/(iPhone|iPod|iPad)/),
    		blackberry: ua.match(/BlackBerry/),
    		android: ua.match(/Android/),
    		microsoft: ua.match(/Windows Phone/),
    		zune: ua.match(/ZuneWP7/)
    	}

    	return brand;
    }
}

export default ImagePreview;
