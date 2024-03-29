defmodule Brando.Content.Var do
  alias Brando.Content.Var

  def types do
    [
      boolean: Var.Boolean,
      file: Var.File,
      text: Var.Text,
      image: Var.Image,
      string: Var.String,
      datetime: Var.Datetime,
      html: Var.Html,
      color: Var.Color,
      select: Var.Select
    ]
  end
end
