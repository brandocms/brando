defmodule Brando.News.Form.PostForm do
  @moduledoc """
  A form for the Post model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  def get_language_choices do
    [[value: "no", text: "Norsk"],
     [value: "en", text: "English"]]
  end

  form "post", [helper: :admin_post_path, class: "grid-form"] do
    fieldset [row_span: 4] do
      field :language, :select,
        [required: true,
        label: "Språk",
        default: "no",
        choices: &__MODULE__.get_language_choices/0]
    end
    fieldset [row_span: 4] do
      field :featured, :checkbox,
        [label: "Vektet post",
        default: false]
    end
    field :header, :text,
      [required: true,
       label: "Overskrift",
       placeholder: "Overskrift"]
    field :lead, :textarea,
      [label: "Ingress"]
    field :body, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-default"]

  end
end