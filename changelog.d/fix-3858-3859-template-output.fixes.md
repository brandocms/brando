- A string a `tablerow` loop reads of a list of strings is escaped once in a tag argument that escapes what it prints, as in a `for` loop: `{% tablerow tag in entry.tags %}{% picture entry.cover { alt: tag } %}{% endtablerow %}` no longer prints `R&amp;amp;D` for `R&D`.

- Stored rich text that holds markup saving it now would refuse (a `<script>`, an `onclick`, a `javascript:` link) renders with that element or attribute removed and the rest of its markup kept, instead of as plain text.
