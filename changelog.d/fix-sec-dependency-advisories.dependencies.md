- Require `phoenix_html` 4.4 and `req_llm` 1.29 for their security fixes: attribute names passed to dynamic attributes are now validated, and an invalid name raises instead of rendering.
  Update a project already on 0.55 with `mix deps.update phoenix_html req_llm jsv`.

- Update `jsv` to 0.26.2 for its security fix.
