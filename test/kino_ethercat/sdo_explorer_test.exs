defmodule KinoEtherCAT.SDOExplorerTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SDOExplorer

  test "parses hex and decimal indices" do
    assert SDOExplorer.parse_integer("0x1018") == {:ok, 0x1018}
    assert SDOExplorer.parse_integer("7") == {:ok, 7}
    assert SDOExplorer.parse_integer("") == {:error, :empty}
  end

  test "parses hex payload bytes and formats binaries" do
    assert SDOExplorer.parse_hex_payload("DE AD BE EF") == {:ok, <<0xDE, 0xAD, 0xBE, 0xEF>>}
    assert SDOExplorer.parse_hex_payload("123") == {:error, :odd_length}

    assert SDOExplorer.format_binary(<<0x41, 0x00, 0x42>>) == %{
             bytes: 3,
             hex: "41 00 42",
             ascii: "A.B"
           }
  end
end
