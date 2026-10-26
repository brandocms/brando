- Image uploads, direct-to-S3 uploads, image processing and the content importer refuse a raster image over 100 megapixels (width × height × pages) on its header, before decoding it; set `config :brando, Brando.Images, max_pixels: …` to change the limit. The dominant colour is read from a small thumbnail.

- An uploaded SVG's size is read without fetching the external DTD its DOCTYPE names, so it can no longer make the server read a local file.

- Pasted module imports are decoded without creating atoms or functions and must be a list of modules; other text shows "This is not an export of block modules." instead of crashing the screen.

- The Cloudflare Stream, Mux and Bunny webhook plugs read at most 1 MiB of a request body before checking its signature, and answer 413 for a larger one.
