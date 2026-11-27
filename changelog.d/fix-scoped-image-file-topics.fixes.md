- In a site with several environments, an image uploading in an open form or in the upload manager no longer takes another environment's image with the same id when that one finishes processing.

- With several sites and the legacy authorization mode, an upload in the upload manager is stored in the environment the editor works in; it stopped with an error before.

- A link into another site or environment (the shared library's link to a customization, or any admin link from a page opened in another environment than the session's) now loads the page, so the upload manager, the navigation and the top bar work in and show the page's site and environment; they kept the old one before.
