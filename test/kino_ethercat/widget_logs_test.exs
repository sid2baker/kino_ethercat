defmodule KinoEtherCAT.WidgetLogsTest do
  use ExUnit.Case, async: false

  require Logger

  alias EtherCAT.{Domain, Master, Slave}
  alias KinoEtherCAT.Runtime.BusResource
  alias KinoEtherCAT.{Runtime, WidgetLogs}

  setup_all do
    if is_nil(Process.whereis(WidgetLogs)) do
      start_supervised!(WidgetLogs)
    end

    :ok
  end

  test "installs the widget log handler and default filter" do
    assert :kino_ethercat_widget_logs in :logger.get_handler_ids()
    assert {:ok, config} = :logger.get_handler_config(:default)

    assert Enum.any?(Map.get(config, :filters, []), fn {id, _filter} ->
             id == :kino_ethercat_widget_logs
           end)
  end

  test "silences routed EtherCAT events before widgets subscribe" do
    event = %{
      level: :info,
      msg: {:string, "[Master] routed"},
      meta: %{application: :ethercat, pid: self()}
    }

    assert WidgetLogs.silence?(event)
  end

  test "routes link-level bus warnings into the bus scope" do
    token = unique_token("redundant-link")

    Logger.log(
      :warning,
      "[Link.Redundant] #{token}",
      application: :ethercat,
      component: :bus
    )

    assert_eventually(fn ->
      bus_logs = Runtime.payload(%BusResource{}).logs
      assert Enum.any?(bus_logs, &String.contains?(&1.text, token))
    end)
  end

  test "widgets can mount later and read buffered logs for their scope" do
    slave_token = unique_token("buffered-slave")

    Logger.log(:warning, "[Slave rack_1] #{slave_token}", application: :ethercat)

    assert_eventually(fn ->
      assert Enum.any?(
               WidgetLogs.entries(%Slave{name: :rack_1}),
               &String.contains?(&1.text, slave_token)
             )
    end)

    WidgetLogs.subscribe(self(), %Slave{name: :rack_1})

    assert_eventually(fn ->
      slave_logs = Runtime.payload(%Slave{name: :rack_1}).logs
      assert Enum.any?(slave_logs, &String.contains?(&1.text, slave_token))
    end)
  end

  test "runtime payloads expose resource-specific log buffers" do
    master_token = unique_token("master")
    slave_token = unique_token("slave")
    domain_token = unique_token("domain")
    bus_token = unique_token("bus")
    dc_token = unique_token("dc")

    Logger.log(:info, "[Master] #{master_token}", application: :ethercat)
    Logger.log(:warning, "[Slave rack_1] #{slave_token}", application: :ethercat)
    Logger.log(:error, "[Domain main] #{domain_token}", application: :ethercat)
    Logger.log(:warning, "[Bus] #{bus_token}", application: :ethercat)
    Logger.log(:info, "[DC] #{dc_token}", application: :ethercat)

    assert_eventually(fn ->
      master_logs = Runtime.payload(%Master{}).logs
      slave_logs = Runtime.payload(%Slave{name: :rack_1}).logs
      domain_logs = Runtime.payload(%Domain{id: :main}).logs
      bus_logs = Runtime.payload(%BusResource{}).logs
      dc_logs = Runtime.payload(default_dc_resource()).logs

      assert Enum.any?(master_logs, &String.contains?(&1.text, master_token))
      refute Enum.any?(master_logs, &String.contains?(&1.text, slave_token))

      assert Enum.any?(slave_logs, &String.contains?(&1.text, slave_token))
      refute Enum.any?(slave_logs, &String.contains?(&1.text, master_token))

      assert Enum.any?(domain_logs, &String.contains?(&1.text, domain_token))
      assert Enum.any?(bus_logs, &String.contains?(&1.text, bus_token))
      assert Enum.any?(dc_logs, &String.contains?(&1.text, dc_token))
    end)
  end

  test "log levels are scoped per resource" do
    on_exit(fn ->
      WidgetLogs.set_level(:master, :all)
      WidgetLogs.set_level({:slave, :rack_1}, :all)
    end)

    assert WidgetLogs.level(:master) == :all
    assert :ok = WidgetLogs.set_level(:master, :warning)
    assert :ok = WidgetLogs.set_level({:slave, :rack_1}, :debug)

    master_token = unique_token("master-level")
    slave_token = unique_token("slave-level")

    Logger.log(:info, "[Master] #{master_token}", application: :ethercat)
    Logger.log(:info, "[Slave rack_1] #{slave_token}", application: :ethercat)

    assert_eventually(fn ->
      master_logs = Runtime.payload(%Master{}).logs
      slave_logs = Runtime.payload(%Slave{name: :rack_1}).logs

      refute Enum.any?(master_logs, &String.contains?(&1.text, master_token))
      assert Enum.any?(slave_logs, &String.contains?(&1.text, slave_token))
      assert WidgetLogs.level(:master) == :warning
      assert WidgetLogs.level({:slave, :rack_1}) == :debug
    end)
  end

  test "clearing logs only removes the targeted scope buffer" do
    master_token = unique_token("clear-master")
    slave_token = unique_token("clear-slave")

    Logger.log(:info, "[Master] #{master_token}", application: :ethercat)
    Logger.log(:info, "[Slave rack_1] #{slave_token}", application: :ethercat)

    assert_eventually(fn ->
      assert Enum.any?(Runtime.payload(%Master{}).logs, &String.contains?(&1.text, master_token))

      assert Enum.any?(
               Runtime.payload(%Slave{name: :rack_1}).logs,
               &String.contains?(&1.text, slave_token)
             )
    end)

    assert :ok = WidgetLogs.clear(:master)

    assert_eventually(fn ->
      refute Enum.any?(Runtime.payload(%Master{}).logs, &String.contains?(&1.text, master_token))

      assert Enum.any?(
               Runtime.payload(%Slave{name: :rack_1}).logs,
               &String.contains?(&1.text, slave_token)
             )
    end)
  end

  defp assert_eventually(fun, attempts \\ 40)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    fun.()
  rescue
    _error in [ExUnit.AssertionError] ->
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
  else
    _ -> :ok
  end

  defp assert_eventually(_fun, 0) do
    flunk("condition was not satisfied in time")
  end

  defp unique_token(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp default_dc_resource do
    cond do
      Code.ensure_loaded?(EtherCAT.DC.Status) and
          function_exported?(EtherCAT.DC.Status, :__struct__, 0) ->
        struct(EtherCAT.DC.Status)

      Code.ensure_loaded?(EtherCAT.DC) and function_exported?(EtherCAT.DC, :__struct__, 0) ->
        struct(EtherCAT.DC)

      true ->
        %{}
    end
  end
end
