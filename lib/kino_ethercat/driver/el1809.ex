defmodule KinoEtherCAT.Driver.EL1809 do
  @moduledoc "Beckhoff EL1809 — 16-channel digital input, 24 V DC."

  @vendor_id 0x00000002
  @product_code 0x07113052

  def vendor_id, do: @vendor_id
  def product_code, do: @product_code

  @behaviour EtherCAT.Slave.Driver

  @impl true
  def process_data_model(_config) do
    [
      ch1: 0x1A00,
      ch2: 0x1A01,
      ch3: 0x1A02,
      ch4: 0x1A03,
      ch5: 0x1A04,
      ch6: 0x1A05,
      ch7: 0x1A06,
      ch8: 0x1A07,
      ch9: 0x1A08,
      ch10: 0x1A09,
      ch11: 0x1A0A,
      ch12: 0x1A0B,
      ch13: 0x1A0C,
      ch14: 0x1A0D,
      ch15: 0x1A0E,
      ch16: 0x1A0F
    ]
  end

  @impl true
  def encode_signal(_pdo, _config, _), do: <<>>

  @impl true
  def decode_signal(_ch, _config, <<_::7, bit::1>>), do: bit
  def decode_signal(_pdo, _config, _), do: 0
end
