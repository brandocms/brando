defmodule <%= base %>.Repo.Migrations.Create<%= scoped %> do
  use Ecto.Migration
<%= if villain_fields != [] do %>  use Brando.Villain.Migration<% end %>

  def change do
    create table(:<%= plural %>) do
<%= for migration <- migrations do %>      <%= migration %>
<% end %><%= for {_, i, _} <- assocs do %>      add <%= inspect i %>, :integer
<% end %>
      timestamps
    end
<%= for index <- indexes do %>    <%= index %>
<% end %>
  end
end
