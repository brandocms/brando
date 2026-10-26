- Liquid written in a synced Markdown source document appears as text on the page instead of being evaluated, so someone who can push to the documentation repository can no longer inject HTML, read template values or break the page with a template error.

- A page that embeds a fragment through a fragment block no longer evaluates the fragment's rendered text as Liquid a second time.

- Liquid in a library title or credit of an image or video, such as a title fetched from YouTube or Vimeo, appears as text in captions instead of being evaluated.
