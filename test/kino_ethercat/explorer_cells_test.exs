defmodule KinoEtherCAT.ExplorerCellsTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SmartCells.SlaveExplorer

  test "slave explorer renders CoE upload and download source" do
    upload =
      SlaveExplorer.to_source(%{
        "surface" => "sdo",
        "slave" => "slave_1",
        "operation" => "upload",
        "index" => "0x1018",
        "subindex" => "0x00"
      })

    assert upload =~ "EtherCAT.upload_sdo(:slave_1, 0x1018, 0x0)"
    assert upload =~ "Base.encode16(binary, case: :upper)"

    download =
      SlaveExplorer.to_source(%{
        "surface" => "sdo",
        "slave" => "slave_1",
        "operation" => "download",
        "index" => "0x7000",
        "subindex" => "1",
        "write_data" => "DE AD BE EF"
      })

    assert download =~ "payload = <<0xDE, 0xAD, 0xBE, 0xEF>>"
    assert download =~ "EtherCAT.download_sdo(:slave_1, 0x7000, 1, payload)"
  end

  test "slave explorer renders register presets and raw writes" do
    read_source =
      SlaveExplorer.to_source(%{
        "surface" => "register",
        "slave" => "slave_2",
        "operation" => "read",
        "register_mode" => "preset",
        "register" => "al_status"
      })

    assert read_source =~ "alias EtherCAT.Bus.Transaction"
    assert read_source =~ "register = Registers.al_status()"
    assert read_source =~ "Registers.decode_al_status(data)"

    write_source =
      SlaveExplorer.to_source(%{
        "surface" => "register",
        "slave" => "slave_2",
        "operation" => "write",
        "register_mode" => "raw",
        "address" => "0x0120",
        "write_data" => "08 00"
      })

    assert write_source =~ "register = {0x120, <<0x08, 0x00>>}"
    assert write_source =~ "Transaction.fpwr(station, register)"
  end

  test "slave explorer renders SII reads and word writes" do
    identity_source =
      SlaveExplorer.to_source(%{
        "surface" => "sii",
        "slave" => "slave_3",
        "operation" => "identity"
      })

    assert identity_source =~ "alias EtherCAT.Slave.SII"
    assert identity_source =~ "SII.read_identity(bus, station)"

    write_source =
      SlaveExplorer.to_source(%{
        "surface" => "sii",
        "slave" => "slave_3",
        "operation" => "write_words",
        "word_address" => "0x0040",
        "write_data" => "34 12"
      })

    assert write_source =~ "payload = <<0x34, 0x12>>"
    assert write_source =~ "SII.write(bus, station, 0x40, payload)"
  end
end
