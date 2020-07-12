defmodule Brando.Lexer.ArgumentTest do
  @moduledoc false

  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Lexer.Argument
  alias Brando.Lexer.Context

  setup do
    ExMachina.Sequence.reset()
  end

  describe "eval" do
    test "evaluate literal" do
      assert 5 == Argument.eval([literal: 5], %Context{})
    end

    test "evaluate unkown field" do
      assert nil == Argument.eval([field: [key: "i"]], %Context{})
      assert nil == Argument.eval([field: [key: "a", key: "b"]], %Context{})
    end

    test "evaluate with known field" do
      assert 5 == Argument.eval([field: [key: "i"]], Context.new(%{"i" => 5}))
      assert 5 == Argument.eval([field: [key: "a", key: "b"]], Context.new(%{"a" => %{"b" => 5}}))
    end

    test "evaluate with array field" do
      obj = Context.new(%{"field" => [%{}, %{"child" => 5}]})

      assert 5 == Argument.eval([field: [key: "field", accessor: 1, key: "child"]], obj)
    end

    test "evaluate with array.first" do
      obj = Context.new(%{"field" => [%{"child" => 5}]})

      assert 5 == Argument.eval([field: [key: "field", key: "first", key: "child"]], obj)
    end

    test "evaluate with array.count" do
      obj = Context.new(%{"field" => [1, 2, 3, 4, 5]})

      assert 5 == Argument.eval([field: [key: "field", key: "count"]], obj)
    end

    test "evaluate with out of bounds array field" do
      obj = Context.new(%{"field" => [%{}, %{"child" => 5}]})
      assert nil == Argument.eval([field: [key: "field", accessor: 5, key: "child"]], obj)
    end

    test "global:category.key" do
      obj = Context.new(%{})

      assert "" == Argument.eval([field: [key: "global", key: "system", key: "key-0"]], obj)

      globals = Factory.build_list(2, :global)
      Factory.insert(:global_category, globals: globals)
      assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}

      globals = Brando.Cache.Globals.get()
      obj = Context.new(%{"globals" => globals})
      global = Argument.eval([field: [key: "global", key: "system", key: "key-0"]], obj)
      assert global.key == "key-0"
    end

    test "link:instagram" do
      identity = Brando.Cache.Identity.get()
      obj = Context.new(%{})
      assert nil == Argument.eval([field: [key: "link", key: "instagram", key: "url"]], obj)
      obj = Context.new(%{"links" => identity.links})

      assert Argument.eval([field: [key: "link", key: "instagram", key: "url"]], obj) ==
               "https://instagram.com/test"
    end

    test "struct atom keys" do
      u1 = Factory.insert(:random_user)
      obj = Context.new(%{"user" => u1})

      assert Argument.eval([field: [key: "user", key: "email"]], obj) ==
               u1.email
    end
  end
end
