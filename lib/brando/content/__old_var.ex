defmodule Brando.Content.OldVar do
  alias Brando.Content.OldVar

  def types do
    [
      boolean: OldVar.Boolean,
      text: OldVar.Text,
      image: OldVar.Image,
      string: OldVar.String,
      datetime: OldVar.Datetime,
      html: OldVar.Html,
      color: OldVar.Color,
      select: OldVar.Select
    ]
  end
end
