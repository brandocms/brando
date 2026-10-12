- **The video cover placeholder is decorative: `alt=""`.** The SVG placeholder
  `Brando.HTML.Video` draws over a video (`cover: :svg`) had
  `alt="Video cover image"`, in English on every public page whatever its
  language. It now has `alt=""` and its `data-cover` wrapper
  `aria-hidden="true"`, so screen readers skip it.
