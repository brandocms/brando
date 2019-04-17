defmodule <%= application_module %>.Factory do
  use ExMachina, repo: <%= application_module %>.Repo
  use Brando.FactoryMixin
end
