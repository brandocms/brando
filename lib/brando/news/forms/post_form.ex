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

  def get_status_choices do
    [[value: "0", text: "Kladd"],
     [value: "1", text: "Venter"],
     [value: "2", text: "Publisert"],
     [value: "3", text: "Slettet"]]
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
      field :status, :select,
        [required: true,
        label: "Status",
        default: "2",
        choices: &__MODULE__.get_status_choices/0]
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
    field :data, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-default"]

  end
end