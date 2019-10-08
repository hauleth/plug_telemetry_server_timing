defmodule Plug.ServerTimingTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @subject Plug.ServerTiming

  doctest @subject

  describe "plug" do
    setup do
      [conn: conn(:get, "/")]
    end

    test "if no events defined then there is no header", %{conn: conn} do
      conn =
        conn
        |> @subject.call([])
        |> resp(:ok, "OK")
        |> send_resp()

      assert [] == get_resp_header(conn, "server-timing")
    end

    test "if defined listener in event then it is present in header", %{conn: conn} do
      opts = Plug.Telemetry.init(event_prefix: [:prefix])

      listen_for([
        {[:prefix, :stop], :duration}
      ])

      conn =
        conn
        |> @subject.call([])
        |> Plug.Telemetry.call(opts)
        |> resp(:ok, "OK")
        |> send_resp()

      assert [header] = get_resp_header(conn, "server-timing")
      assert header =~ "prefix.stop.duration;dur="
    end

    test "custom Telemetry events also can be recorded", %{conn: conn} do
      listen_for([
        {[:foo], :bar}
      ])

      conn =
        conn
        |> @subject.call([])

      dur = System.convert_time_unit(2, :millisecond, :native)
      :telemetry.execute([:foo], %{bar: dur})

      conn =
        conn
        |> resp(:ok, "OK")
        |> send_resp()

      assert [header] = get_resp_header(conn, "server-timing")
      assert header =~ "foo.bar;dur=2"
    end

    test "events that aren't listened are ignored", %{conn: conn} do
      opts = Plug.Telemetry.init(event_prefix: [:prefix])

      listen_for([
        {[:prefix, :stop], :duration}
      ])

      conn =
        conn
        |> @subject.call([])
        |> Plug.Telemetry.call(opts)

      dur = System.convert_time_unit(2, :millisecond, :native)
      :telemetry.execute([:foo], %{bar: dur})

      conn =
        conn
        |> resp(:ok, "OK")
        |> send_resp()

      assert [header] = get_resp_header(conn, "server-timing")
      assert header =~ "prefix.stop.duration;dur="
      refute header =~ "foo.bar"
    end
  end

  defp listen_for(events) do
    @subject.install(events)

    on_exit(fn ->
      for {event, name} <- events do
        :telemetry.detach({@subject, event, name})
      end
    end)
  end
end
