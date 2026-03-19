defmodule KinoEtherCAT.SmartCellsTest do
  use ExUnit.Case, async: true

  alias KinoEtherCAT.SmartCells.{
    Setup,
    Simulator,
    SimulatorConfig,
    SlaveExplorer,
    Visualizer
  }

  test "setup cell persists static startup code from discovered slaves" do
    source =
      Setup.to_source(%{
        "interface" => "eth0",
        "domains" => [
          %{
            "id" => "fast",
            "cycle_time_ms" => 1,
            "miss_threshold" => 1_000
          },
          %{
            "id" => "slow",
            "cycle_time_ms" => 4,
            "miss_threshold" => 250
          }
        ],
        "dc_enabled" => true,
        "dc_cycle_ns" => 1_000_000,
        "await_lock" => true,
        "warmup_cycles" => 8,
        "slaves" => [
          %{
            "name" => "coupler",
            "discovered_name" => "coupler",
            "driver" => "",
            "domain_id" => ""
          },
          %{
            "name" => "slave_1",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "fast"
          },
          %{
            "name" => "slave_2",
            "discovered_name" => "slave_2",
            "driver" => "KinoEtherCAT.Driver.EL2809",
            "domain_id" => "slow"
          }
        ]
      })

    assert source =~ ~s(interface: "eth0")

    assert source =~
             ~s(%EtherCAT.Domain.Config{id: :fast, cycle_time_us: 1000, miss_threshold: 1000})

    assert source =~
             ~s(%EtherCAT.Domain.Config{id: :slow, cycle_time_us: 4000, miss_threshold: 250})

    assert source =~ "slaves: ["
    assert source =~ ~s(%EtherCAT.Slave.Config{name: :coupler, target_state: :op})
    assert source =~ ~s(driver: KinoEtherCAT.Driver.EL1809)
    assert source =~ ~s(process_data: {:all, :fast})
    assert source =~ ~s(process_data: {:all, :slow})
    assert source =~ ~s(warmup_cycles: 8)
    assert source =~ "start_opts = ["
    assert source =~ "setup_result ="
    assert source =~ "with :ok <- EtherCAT.start(start_opts),"
    assert source =~ "Kino.Markdown.new"
    assert source =~ "## EtherCAT setup failed"
    refute source =~ "transport: :udp"
    refute source =~ "start_master = fn"
    refute source =~ ":eaddrinuse"
    refute source =~ ":ok = EtherCAT.await_running()"
    refute source =~ ":ok = EtherCAT.await_operational()"
    assert source =~ "Kino.Layout.tabs("
    assert source =~ "Master: KinoEtherCAT.master()"
    assert source =~ ~s|"Task Manager": KinoEtherCAT.diagnostics()|
    refute source =~ "String.to_atom"
    refute source =~ "EtherCAT.configure_slave"
    refute source =~ "backup_interface"
    refute source =~ "activation_mode"
  end

  test "setup cell migrates legacy single-domain attrs into multi-domain startup config" do
    source =
      Setup.to_source(%{
        "interface" => "eth0",
        "domain_id" => "main",
        "cycle_time_us" => 1_000,
        "dc_enabled?" => false,
        "slaves" => [
          %{
            "name" => "sensor_a",
            "discovered_name" => "slave_1",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "main"
          }
        ]
      })

    assert source =~ ~s(dc: nil)

    assert source =~
             ~s(%EtherCAT.Domain.Config{id: :main, cycle_time_us: 1000, miss_threshold: 1000})

    assert source =~ "%EtherCAT.Slave.Config{"
    assert source =~ "name: :sensor_a"
    assert source =~ "driver: KinoEtherCAT.Driver.EL1809"
    assert source =~ "process_data: {:all, :main}"
    assert source =~ "target_state: :op"

    refute source =~ "transport: :udp"
    refute source =~ "EtherCAT.configure_slave"
    refute source =~ "activation_mode"
  end

  test "setup cell renders udp transport source without simulator-specific code" do
    source =
      Setup.to_source(%{
        "transport" => "udp",
        "port" => 34_980,
        "dc_enabled" => false,
        "domains" => [
          %{"id" => "main", "cycle_time_ms" => 10, "miss_threshold" => 1_000}
        ],
        "slaves" => [
          %{
            "name" => "inputs",
            "discovered_name" => "inputs",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "main"
          }
        ]
      })

    assert source =~ "start_opts = ["
    assert source =~ "transport: :udp"
    assert source =~ "host: {127, 0, 0, 2}"
    assert source =~ "port: 34980"
    assert source =~ "bind_ip: {127, 0, 0, 1}"
    assert source =~ "frame_timeout_ms: 10"
    assert source =~ "with :ok <- EtherCAT.start(start_opts),"
    refute source =~ "Enum.reduce_while"
    refute source =~ "Process.sleep(20)"
    refute source =~ "start_master = fn"
    assert source =~ "driver: KinoEtherCAT.Driver.EL1809"
    assert source =~ ~s(process_data: {:all, :main})
    refute source =~ "EtherCAT.Simulator"
    refute source =~ "simulator_ip"
  end

  test "setup cell renders redundant raw transport source" do
    source =
      Setup.to_source(%{
        "transport" => "raw_redundant",
        "interface" => "veth-m0",
        "backup_interface" => "veth-m1",
        "dc_enabled" => false,
        "domains" => [
          %{"id" => "main", "cycle_time_ms" => 10, "miss_threshold" => 1_000}
        ],
        "slaves" => [
          %{
            "name" => "inputs",
            "discovered_name" => "inputs",
            "driver" => "KinoEtherCAT.Driver.EL1809",
            "domain_id" => "main"
          }
        ]
      })

    assert source =~ ~s(interface: "veth-m0")
    assert source =~ ~s(backup_interface: "veth-m1")
    refute source =~ "transport: :udp"
    refute source =~ "frame_timeout_ms: 10"
  end

  test "slave explorer capture surface renders scaffold source with default modules" do
    source =
      SlaveExplorer.to_source(%{
        "surface" => "capture",
        "slave" => "slave_1",
        "capture_snapshot" => capture_snapshot()
      })

    assert source =~ "defmodule EtherCAT.Drivers.Slave1 do"
    assert source =~ "defmodule EtherCAT.Drivers.Slave1.Simulator do"
    assert source =~ "@behaviour EtherCAT.Slave.Driver"
    assert source =~ "@behaviour EtherCAT.Simulator.DriverAdapter"
    assert source =~ "ch1: 0x1A00"
    assert {:ok, _quoted} = Code.string_to_quoted(source)
    refute source =~ "EtherCAT.Capture.capture("
    refute source =~ "definition_options ="
    refute source =~ "EtherCAT.Capture.gen_driver("
    refute source =~ "EtherCAT.Capture.gen_simulator("
    refute source =~ "EtherCAT.Capture.render_driver("
  end

  test "slave explorer capture surface renders scaffold source with overrides and sdos" do
    source =
      SlaveExplorer.to_source(%{
        "surface" => "capture",
        "slave" => "slave_1",
        "capture_snapshot" => capture_snapshot(mailbox_capture_fixture()),
        "driver_name" => "EL1809",
        "capture_sdos" => "0x1008:0x00\n0x1009:0x00",
        "capture_signal_entries" => [
          %{
            "key" => "input:1a00",
            "name" => "left_input",
            "direction" => "input",
            "pdo_index" => 0x1A00,
            "bit_size" => 1
          }
        ]
      })

    assert source =~ "defmodule EtherCAT.Drivers.EL1809 do"
    assert source =~ "defmodule EtherCAT.Drivers.EL1809.Simulator do"
    assert source =~ "left_input: 0x1A00"
    assert source =~ "def mailbox_config(_config)"
    assert {:ok, _quoted} = Code.string_to_quoted(source)
    refute source =~ "String.to_atom"
    refute source =~ "EtherCAT.Capture.gen_driver("
    refute source =~ "EtherCAT.Capture.capture("
  end

  test "visualizer cell renders signal widget calls" do
    source =
      Visualizer.to_source(%{
        "selected" => [
          %{
            "key" => "outputs.ch1",
            "slave" => "outputs",
            "signal" => "ch1",
            "direction" => "output",
            "bit_size" => 1,
            "default_widget" => "switch",
            "widget" => "auto",
            "label" => "Output 1"
          },
          %{
            "key" => "inputs.ch1",
            "slave" => "inputs",
            "signal" => "ch1",
            "direction" => "input",
            "bit_size" => 1,
            "default_widget" => "led",
            "widget" => "auto",
            "label" => nil
          },
          %{
            "key" => "inputs.temperature",
            "slave" => "inputs",
            "signal" => "temperature",
            "direction" => "input",
            "bit_size" => 16,
            "default_widget" => "value",
            "widget" => "value",
            "label" => "Temperature"
          }
        ]
      })

    assert source =~ "widgets = ["
    assert source =~ ~s/KinoEtherCAT.Widgets.switch(:outputs, :ch1, label: "Output 1")/
    assert source =~ ~s/KinoEtherCAT.Widgets.led(:inputs, :ch1)/
    assert source =~ ~s/KinoEtherCAT.Widgets.value(:inputs, :temperature, label: "Temperature")/
    assert source =~ "Kino.Layout.grid(widgets, columns: 2)"
    assert source =~ "Kino.nothing()"
    refute source =~ "KinoEtherCAT.Widgets.dashboard"
    refute source =~ "String.to_atom"
  end

  test "visualizer cell returns empty source without selected signals" do
    assert Visualizer.to_source(%{}) == ""
  end

  test "simulator cell renders a simulator-only source with ordered devices" do
    source =
      Simulator.to_source(%{
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100", "name" => "coupler"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "rack_outputs"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "rack_inputs"},
          %{"id" => "4", "driver" => "KinoEtherCAT.Driver.EL2809"}
        ],
        "connections" => [
          %{
            "source_id" => "2",
            "source_signal" => "ch1",
            "target_id" => "3",
            "target_signal" => "ch1"
          }
        ]
      })

    assert source =~ "alias EtherCAT.Simulator"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EK1100, name: :coupler)"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :rack_outputs)"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EL1809, name: :rack_inputs)"
    assert source =~ "Slave.from_driver(KinoEtherCAT.Driver.EL2809, name: :outputs)"
    assert transport_start_snippet(source, SimulatorConfig.default_transport())
    assert source =~ ":ok = Slave.connect({:rack_outputs, :ch1}, {:rack_inputs, :ch1})"
    assert source =~ "Kino.Layout.tabs("
    assert source =~ "Introduction: KinoEtherCAT.introduction()"
    assert source =~ "Simulator: KinoEtherCAT.simulator()"
    assert source =~ "Faults: KinoEtherCAT.simulator_faults()"
    refute source =~ "EtherCAT.start("
    refute source =~ "KinoEtherCAT.diagnostics()"
    refute source =~ "String.to_atom"
  end

  test "simulator cell seeds one default loopback connection for fresh attrs" do
    source = Simulator.to_source(%{})

    assert source =~ ":ok = Slave.connect({:outputs, :ch1}, {:inputs, :ch1})"
  end

  test "simulator cell defaults to the best available transport" do
    assert SimulatorConfig.normalize_transport(nil) == SimulatorConfig.default_transport()
    assert SimulatorConfig.normalize_transport("udp") == "udp"

    source = Simulator.to_source(%{})

    assert transport_start_snippet(source, SimulatorConfig.default_transport())
  end

  test "simulator cell renders raw socket transport source" do
    source =
      Simulator.to_source(%{
        "transport" => "raw_socket",
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100", "name" => "coupler"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "inputs"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "outputs"}
        ]
      })

    assert source =~ ~s|Simulator.start(devices: devices, raw: [interface: "veth-s0"])|
    refute source =~ "simulator_ip ="
    refute source =~ "udp:"
  end

  test "simulator cell omits introduction tab in expert mode" do
    source =
      Simulator.to_source(%{
        "expert_mode" => true,
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100", "name" => "coupler"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "inputs"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "outputs"}
        ]
      })

    assert source =~ "Kino.Layout.tabs("
    refute source =~ "Introduction: KinoEtherCAT.introduction()"
    assert source =~ "Simulator: KinoEtherCAT.simulator()"
    assert source =~ "Faults: KinoEtherCAT.simulator_faults()"
  end

  test "simulator cell renders redundant raw transport source" do
    source =
      Simulator.to_source(%{
        "transport" => "raw_socket_redundant",
        "selected" => [
          %{"id" => "1", "driver" => "KinoEtherCAT.Driver.EK1100", "name" => "coupler"},
          %{"id" => "2", "driver" => "KinoEtherCAT.Driver.EL1809", "name" => "inputs"},
          %{"id" => "3", "driver" => "KinoEtherCAT.Driver.EL2809", "name" => "outputs"}
        ]
      })

    assert source =~ "topology: :redundant"
    assert source =~ ~s(raw: [primary: [interface: "veth-s0"], secondary: [interface: "veth-s1"]])
  end

  defp capture_snapshot(capture \\ capture_fixture()) do
    capture
    |> :erlang.term_to_binary(compressed: 6)
    |> Base.encode64(padding: false)
  end

  defp capture_fixture do
    identity = %{
      vendor_id: 0x0000_0002,
      product_code: 0x0711_3052,
      revision: 0,
      serial_number: 0
    }

    pdo_configs =
      Enum.map(0..15, fn offset ->
        %{
          index: 0x1A00 + offset,
          direction: :input,
          sm_index: 3,
          bit_size: 1,
          bit_offset: offset
        }
      end)

    %{
      format: 1,
      captured_at: "2026-03-14T00:00:00Z",
      source: %{
        master_state: :preop_ready,
        bus: %{transport: :test},
        slave_name: :slave_1,
        station: 1
      },
      slave: %{
        name: :slave_1,
        station: 1,
        al_state: :preop,
        identity: identity,
        esc: %{fmmu_count: 4, sm_count: 4},
        driver: EtherCAT.Slave.Driver.Default,
        coe: false,
        configuration_error: nil
      },
      sii: %{
        identity: identity,
        mailbox_config: %{recv_offset: 0, recv_size: 0, send_offset: 0, send_size: 0},
        sm_configs: [],
        pdo_configs: pdo_configs
      },
      sdos: [],
      warnings: []
    }
  end

  defp mailbox_capture_fixture do
    Map.put(capture_fixture(), :sdos, [%{index: 0x1008, subindex: 0x00, data: <<"EL1809", 0>>}])
  end

  defp transport_start_snippet(source, "udp") do
    source =~ "simulator_ip = {127, 0, 0, 2}" and
      source =~ "Simulator.start(devices: devices, udp: [ip: simulator_ip, port: 34980])"
  end

  defp transport_start_snippet(source, "raw_socket") do
    source =~ ~s|Simulator.start(devices: devices, raw: [interface: "veth-s0"])|
  end

  defp transport_start_snippet(source, "raw_socket_redundant") do
    source =~ "topology: :redundant" and
      source =~ ~s(raw: [primary: [interface: "veth-s0"], secondary: [interface: "veth-s1"]])
  end
end
