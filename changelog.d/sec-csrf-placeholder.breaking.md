- `$csrftoken` is filled in only as the whole value of an `<input type="hidden" name="_csrf_token">`; anywhere else it stays as text.
  A form component set with `config :brando, Brando.Forms, component: …` renders `@csrf_token` as `<input type="hidden" name="_csrf_token" value={@csrf_token} />`.
