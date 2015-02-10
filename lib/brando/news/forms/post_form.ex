defmodule Brando.News.Form.PostForm do
  @moduledoc """
  A form for the Post model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  form "post", [helper: :admin_post_path, class: "grid-form"] do
    field :header, :text,
      [required: true,
       label: "Overskrift",
       placeholder: "Overskrift"]
    field :body, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-default"]

  end
end