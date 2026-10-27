- A service linked to a page takes the description that page publishes, through its blueprint's `meta_schema` fallbacks (an intro, say), instead of the raw meta description field.

- Text taken from rendered blocks (`Brando.Blueprint.Value.rendered_text/2`, used for fallback meta descriptions, service descriptions and AI context) no longer carries pieces of HTML comments such as `] -->`, nor `<script>` and `<style>` contents.
