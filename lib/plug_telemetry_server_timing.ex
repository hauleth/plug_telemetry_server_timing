defmodule Plug.Telemetry.ServerTiming do
  @behaviour Plug

  @moduledoc """
  This plug provide support for [`Server-Timing`][st] header that allows to
  display server-side measurements in browser developer tools and access it
  programatically via Performance API in JavaScript.

  ## Usage

  Just add it as a plug into your pipeline:

  ```
  plug Plug.Telemetry.ServerTiming
  ```

  And call `install/1` with list of `{event_name, measurement}` in your
  application startup, for example for Phoenix and Ecto application:

  ```
  Plug.Telemetry.ServerTiming.install([
    {[:phoenix, :endpoint, :stop], :duration},
    {[:my_app, :repo, :query], :queue_time},
    {[:my_app, :repo, :query], :query_time},
    {[:my_app, :repo, :query], :decode_time}
  ])
  ```

  And then it will be visible in your DevTools.

  ### Important

  You need to place this plug **BEFORE** `Plug.Telemetry` call as otherwise it
  will not see it's events (`before_send` callbacks are called in reverse order
  of declaration, so this one need to be added before `Plug.Telemetry` one.

  ## Caveats

  This will not respond with events that happened in separate processes, only
  events that happened in the Plug process will be recorded.

  ### WARNING

  Current specification of `Server-Timing` do not provide a way to specify event
  start time, which mean, that the data displayed in the DevTools isn't trace
  report (like the content of the "regular" HTTP timings) but raw dump of the data
  displayed as a bars. This can be a little bit confusing, but right now there is
  nothing I can do about it.

  [st]: https://w3c.github.io/server-timing/#the-server-timing-header-field
  """

  import Plug.Conn

  @impl true
  @doc false
  def init(opts), do: opts

  @impl true
  @doc false
  def call(conn, _opts) do
    Process.put(__MODULE__, {true, %{}})

    register_before_send(conn, &timings/1)
  end

  @doc """
  Define which events should be available within response headers.
  """
  @spec install(events) :: :ok when events: map() | [{:telemetry.event_name(), atom()}]
  def install(events) do
    for {name, metric} <- events do
      :ok = :telemetry.attach({__MODULE__, name, metric}, name, &__MODULE__.__handle__/4, metric)
    end

    :ok
  end

  @doc false
  def __handle__(metric_name, measurements, _metadata, metric) do
    with %{^metric => duration} <- measurements,
         {true, data} <- Process.get(__MODULE__) do
      Process.put(
        __MODULE__,
        {true, Map.update(data, {metric_name, metric}, duration, &(&1 + duration))}
      )

      :ok
    else
      _ -> :ok
    end
  end

  defp timings(conn) do
    {_, measurements} = Process.get(__MODULE__, {false, %{}})

    if measurements == %{} do
      conn
    else
      put_resp_header(conn, "server-timing", render_measurements(measurements))
    end
  end

  defp render_measurements(measurements) do
    millis = System.convert_time_unit(1, :millisecond, :native)

    measurements
    |> Enum.map(fn {{metric_name, metric}, measurement} ->
      name = "#{Enum.join(metric_name, ".")}.#{metric}"
      duration = measurement / millis

      "#{name};dur=#{duration}"
    end)
    |> Enum.join(",")
  end
end
