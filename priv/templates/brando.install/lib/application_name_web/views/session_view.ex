defmodule <%= application_module %>Web.SessionView do
  use <%= application_module %>Web, :view

  def render("show.json", %{jwt: jwt, user: user}) do
    %{jwt: jwt, user: user}
  end

  def render("error.json", _) do
    %{error: "Feil ved innlogging"}
  end

  def render("delete.json", _) do
    %{ok: true}
  end

  def render("forbidden.json", %{error: error}) do
    %{error: error}
  end

  def render("expired.json", _) do
    %{error: "expired"}
  end

  def render("ok.json", _) do
    %{ok: true}
  end
end
