defmodule KinoEtherCAT.Driver.EL3202 do
  @moduledoc "Beckhoff EL3202 — 2-channel PT100 RTD temperature input."

  @behaviour EtherCAT.Slave.Driver

  @vendor_id 0x00000002
  @product_code 0x0C823052

  def vendor_id, do: @vendor_id
  def product_code, do: @product_code

  @impl true
  def identity do
    %{vendor_id: @vendor_id, product_code: @product_code}
  end

  @impl true
  def simulator_definition(_config), do: nil

  @impl true
  def process_data_model(_config) do
    [channel1: 0x1A00, channel2: 0x1A01]
  end

  @impl true
  def mailbox_config(_config) do
    [
      {:sdo_download, 0x8000, 0x19, <<8::16-little>>},
      {:sdo_download, 0x8010, 0x19, <<8::16-little>>}
    ]
  end

  @impl true
  def encode_signal(_pdo, _config, _value), do: <<>>

  @impl true
  def decode_signal(:channel1, _config, <<
        _::1,
        error::1,
        _::2,
        _::2,
        overrange::1,
        underrange::1,
        toggle::1,
        state::1,
        _::6,
        value::16-little
      >>) do
    %{
      ohms: value / 16.0,
      overrange: overrange == 1,
      underrange: underrange == 1,
      error: error == 1,
      invalid: state == 1,
      toggle: toggle
    }
  end

  def decode_signal(:channel2, _config, <<
        _::1,
        error::1,
        _::2,
        _::2,
        overrange::1,
        underrange::1,
        toggle::1,
        state::1,
        _::6,
        value::16-little
      >>) do
    %{
      ohms: value / 16.0,
      overrange: overrange == 1,
      underrange: underrange == 1,
      error: error == 1,
      invalid: state == 1,
      toggle: toggle
    }
  end

  def decode_signal(_pdo, _config, _), do: nil
end
