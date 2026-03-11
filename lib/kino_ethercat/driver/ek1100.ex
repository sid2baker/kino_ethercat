defmodule KinoEtherCAT.Driver.EK1100 do
  @moduledoc "Beckhoff EK1100 — EtherCAT coupler."

  @behaviour EtherCAT.Slave.Driver

  alias EtherCAT.Simulator.Slave.Definition

  @vendor_id 0x0000_0002
  @product_code 0x044C_2C52

  def vendor_id, do: @vendor_id
  def product_code, do: @product_code

  @impl true
  def identity do
    %{vendor_id: @vendor_id, product_code: @product_code}
  end

  @impl true
  def simulator_definition(_config) do
    Definition.build(:coupler,
      vendor_id: @vendor_id,
      product_code: @product_code,
      serial_number: 0
    )
  end

  @impl true
  def process_data_model(_config), do: []

  @impl true
  def encode_signal(_signal, _config, _value), do: <<>>

  @impl true
  def decode_signal(_signal, _config, _raw), do: nil
end
