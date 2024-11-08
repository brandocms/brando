defmodule Brando.Villain.LiquexParser do
  use Liquex.Parser,
    tags: [
      Brando.Villain.Tags.HeadlessRef,
      Brando.Villain.Tags.Inspect,
      Brando.Villain.Tags.Ref,
      Brando.Villain.Tags.Link,
      Brando.Villain.Tags.Picture,
      Brando.Villain.Tags.Video,
      Brando.Villain.Tags.Route,
      Brando.Villain.Tags.RouteI18n,
      Brando.Villain.Tags.Fragment,
      Brando.Villain.Tags.Hide,
      Brando.Villain.Tags.EndHide,
      Brando.Villain.Tags.T,
      Brando.Villain.Tags.Datasource,
      Brando.Villain.Tags.EndDatasource
    ]
end
