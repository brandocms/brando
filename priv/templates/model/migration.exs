defmodule <%= base %>.Repo.Migrations.Create<%= scoped %> do
  use Ecto.Migration

  def change do
    create table(:<%= plural %>) do
<%= for {k, v} <- attrs do %>      add <%= inspect k %>, <%= inspect(mig_types[k]) %><%= defaults[k] %>
<% end %><%= for {_, i, _} <- assocs do %>      add <%= inspect i %>, :integer
<% end %>
      timestamps
    end
<%= for index <- indexes do %>    <%= index %>
<% end %>
  end
end
