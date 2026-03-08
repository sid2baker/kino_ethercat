defmodule KinoEtherCAT.SourceTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Source

  test "atom_literal only quotes atoms when required" do
    assert Source.atom_literal("slave_1") == ":slave_1"
    assert Source.atom_literal("main") == ":main"
    assert Source.atom_literal(" temperature sensor ") == ~s(:"temperature sensor")
  end

  test "module_literal only accepts module aliases" do
    assert Source.module_literal("MyApp.Driver") == {:ok, "MyApp.Driver"}
    assert Source.module_literal(" Elixir.MyApp.Driver ") == {:ok, "Elixir.MyApp.Driver"}
    assert Source.module_literal("Module.concat(MyApp, Driver)") == :error
  end
end
