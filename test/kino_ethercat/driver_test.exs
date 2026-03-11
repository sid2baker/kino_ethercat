defmodule KinoEtherCAT.DriverTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.Driver

  test "all/0 exposes assignable built-in drivers from their identity callbacks" do
    modules = Driver.all() |> Enum.map(& &1.module)

    assert KinoEtherCAT.Driver.EL1809 in modules
    assert KinoEtherCAT.Driver.EL2809 in modules
    assert KinoEtherCAT.Driver.EL3202 in modules
    refute KinoEtherCAT.Driver.EK1100 in modules
  end

  test "simulator_all/0 exposes simulator-capable built-in drivers" do
    modules = Driver.simulator_all() |> Enum.map(& &1.module)

    assert KinoEtherCAT.Driver.EK1100 in modules
    assert KinoEtherCAT.Driver.EL1809 in modules
    assert KinoEtherCAT.Driver.EL2809 in modules
    refute KinoEtherCAT.Driver.EL3202 in modules
  end

  test "lookup/1 matches assignable drivers by identity with revision tolerance" do
    assert {:ok, entry} =
             Driver.lookup(%{
               vendor_id: 0x0000_0002,
               product_code: 0x0711_3052,
               revision: 0xDEAD_BEEF
             })

    assert entry.module == KinoEtherCAT.Driver.EL1809
    assert :error == Driver.lookup(%{vendor_id: 0x0000_0002, product_code: 0x044C_2C52})
  end
end
