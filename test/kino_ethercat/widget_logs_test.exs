defmodule KinoEtherCAT.WidgetLogsTest do
  use ExUnit.Case, async: false

  require Logger

  alias EtherCAT.{Bus, Domain, Master, Slave}
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

  test "silences routed events only while a widget scope is subscribed" do
    event = %{
      level: :info,
      msg: {:string, "[Master] routed"},
      meta: %{application: :ethercat, pid: self()}
    }

    refute WidgetLogs.silence?(event)

    subscriber =
      spawn(fn ->
        receive do
        after
          :infinity -> :ok
        end
      end)

    WidgetLogs.subscribe(subscriber, :master)

    assert_eventually(fn ->
      assert WidgetLogs.silence?(event)
    end)

    Process.exit(subscriber, :kill)

    assert_eventually(fn ->
      refute WidgetLogs.silence?(event)
    end)
  end

  test "runtime payloads expose resource-specific log buffers" do
    master_token = unique_token("master")
    slave_token = unique_token("slave")
    domain_token = unique_token("domain")
    bus_token = unique_token("bus")
    dc_token = unique_token("dc")

    WidgetLogs.subscribe(self(), %Master{})
    WidgetLogs.subscribe(self(), %Slave{name: :rack_1})
    WidgetLogs.subscribe(self(), %Domain{id: :main})
    WidgetLogs.subscribe(self(), struct(Bus))
    WidgetLogs.subscribe(self(), default_dc_resource())

    Logger.log(:info, "[Master] #{master_token}", application: :ethercat)
    Logger.log(:warning, "[Slave rack_1] #{slave_token}", application: :ethercat)
    Logger.log(:error, "[Domain main] #{domain_token}", application: :ethercat)
    Logger.log(:warning, "[Bus] #{bus_token}", application: :ethercat)
    Logger.log(:info, "[DC] #{dc_token}", application: :ethercat)

    assert_eventually(fn ->
      master_logs = Runtime.payload(%Master{}).logs
      slave_logs = Runtime.payload(%Slave{name: :rack_1}).logs
      domain_logs = Runtime.payload(%Domain{id: :main}).logs
      bus_logs = Runtime.payload(struct(Bus)).logs
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
