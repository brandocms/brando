- Option labels in a select, multi-select or radio are escaped, so a label written as HTML shows its tags.
  Pass a label built in code that needs markup as `Phoenix.HTML.raw(html)`, with any stored value in it escaped with `Phoenix.HTML.html_escape/1`.
