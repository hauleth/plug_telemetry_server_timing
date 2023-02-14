defmodule Plug.ServerTimingTest do
  use ExUnit.Case, async: false
  use Plug.Test

  @subject Plug.Telemetry.ServerTiming

  doctest @subject

  ExUnit.Case.register_attribute(__MODULE__, :events, accumulate: true)

  setup ctx do
    events = ctx.registered.events

    @subject.install(events)

    on_exit(fn ->
      for %{id: {@subject, _} = id} <- :telemetry.list_handlers([]) do
        :telemetry.detach(id)
      end
    end)
  end

  test "if no events defined then there is no header" do
    conn = request()

    assert [] == get_resp_header(conn, "server-timing")
  end

  @events {[:prefix, :stop], :duration}
  test "if defined listener in event then it is present in header" do
    conn = request([{Plug.Telemetry, event_prefix: [:prefix]}])

    assert [measure] = get_timings(conn)
    assert {"prefix.stop.duration", %{"dur" => _}} = measure
  end

  @events {[:foo], :bar}
  test "custom Telemetry events also can be recorded" do
    conn = request()

    dur = System.convert_time_unit(2, :millisecond, :native)
    :telemetry.execute([:foo], %{bar: dur})

    assert [measure] = get_timings(conn)
    assert {"foo.bar", %{"dur" => "2.000"}} = measure
  end

  @events {[:foo], :bar}
  @events {[:bar], :baz}
  test "two different events are recorded" do
    conn = request()

    dur = System.convert_time_unit(2, :millisecond, :native)
    :telemetry.execute([:foo], %{bar: dur})
    :telemetry.execute([:bar], %{baz: 0})

    timings = get_timings(conn)
    assert {"foo.bar", %{"dur" => "2.000"}} = List.keyfind(timings, "foo.bar", 0)
    assert {"bar.baz", %{"dur" => "0.000"}} = List.keyfind(timings, "bar.baz", 0)
  end

  @events {[:foo], :bar}
  @events {[:foo], :baz}
  test "two measurements for same event are recorded" do
    conn = request()

    dur = System.convert_time_unit(2500, :microsecond, :native)
    :telemetry.execute([:foo], %{bar: dur, baz: 0})

    timings = get_timings(conn)
    assert {"foo.bar", %{"dur" => "2.500"}} = List.keyfind(timings, "foo.bar", 0)
    assert {"foo.baz", %{"dur" => "0.000"}} = List.keyfind(timings, "foo.baz", 0)
  end

  @events {[:foo], :bar, description: "Hi"}
  test "we can add description to the measurement" do
    conn = request()

    :telemetry.execute([:foo], %{bar: 0})

    timings = get_timings(conn)
    assert {"foo.bar", %{"desc" => "Hi"}} = List.keyfind(timings, "foo.bar", 0)
  end

  @events {[:foo], :bar, name: "qux"}
  test "we can change name of the produced value" do
    conn = request()

    :telemetry.execute([:foo], %{bar: 0})

    timings = get_timings(conn)
    assert {"qux", _} = List.keyfind(timings, "qux", 0)
    refute List.keyfind(timings, "foo.bar", 0)
  end

  @events {[:prefix, :stop], :duration}
  test "events that aren't listened are ignored" do
    conn = request([{Plug.Telemetry, event_prefix: [:prefix]}])

    dur = System.convert_time_unit(2, :millisecond, :native)
    :telemetry.execute([:foo], %{bar: dur})

    assert [measure] = get_timings(conn)
    assert {"prefix.stop.duration", %{"dur" => _}} = measure
  end

  @events {[:foo], :bar}
  test "when disabled the metrics aren't recorded" do
    Application.put_env(:plug_telemetry_server_timing, :enabled, false)

    conn = request()

    dur = System.convert_time_unit(2, :millisecond, :native)
    :telemetry.execute([:foo], %{bar: dur})

    assert [] == get_timings(conn)
  after
    Application.put_env(:plug_telemetry_server_timing, :enabled, true)
  end

  defp request(plugs \\ []) do
    opts = @subject.init([])

    conn =
      conn(:get, "/")
      |> resp(:ok, "OK")
      |> @subject.call(opts)

    Enum.reduce_while(plugs, conn, fn
      _plug, %Plug.Conn{halted: true} -> {:halt, conn}
      {mod, opts}, conn -> {:cont, mod.call(conn, mod.init(opts))}
    end)
  end

  # Fetch and parse metrics from the Plug.Conn
  defp get_timings(conn) do
    entries =
      conn
      |> try_send_resp()
      |> get_resp_header("server-timing")

    Enum.flat_map(entries, &decode/1)
  end

  defp try_send_resp(%Plug.Conn{state: :sent} = conn), do: conn
  defp try_send_resp(conn), do: send_resp(conn)

  defp decode(row) do
    for measure <- String.split(row, ",", trim: true) do
      [name | kv] = String.split(measure, ";", trim: true)

      values =
        for entry <- kv, into: %{} do
          [key, value] =
            entry
            |> String.trim()
            |> String.split("=", limit: 2)

          {key, value}
        end

      {name, values}
    end
  end
end
