defmodule Brando.Villain.LiquexParser do
  alias Brando.Villain.Tags

  use Liquex.Parser,
    tags: [
      Tags.HeadlessRef,
      Tags.Ref,
      Tags.Picture,
      Tags.Route,
      Tags.RouteI18n,
      Tags.Fragment,
      Tags.Hide,
      Tags.EndHide
    ]
end
