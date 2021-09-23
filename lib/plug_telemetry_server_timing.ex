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
    enabled = Application.fetch_env!(:plug_telemetry_server_timing, :enabled)

    if enabled do
      start = System.monotonic_time(:millisecond)
      Process.put(__MODULE__, {enabled, []})
      register_before_send(conn, &timings(&1, start))
    else
      conn
    end
  end

  @type events() :: [event()]
  @type event() ::
          {:telemetry.event_name(), atom()}
          | {:telemetry.event_name(), atom(), keyword() | map()}

  @doc """
  Define which events should be available within response headers.
  """
  @spec install(events) :: :ok when events: map() | [{:telemetry.event_name(), atom()}]
  def install(events) do
    for event <- events,
        {name, metric, opts} = normalise(event) do
      :ok =
        :telemetry.attach(
          {__MODULE__, name, metric},
          name,
          &__MODULE__.__handle__/4,
          {metric, opts}
        )
    end

    :ok
  end

  defp normalise({name, metric}), do: {name, metric, %{}}
  defp normalise({name, metric, opts}) when is_map(opts), do: {name, metric, opts}
  defp normalise({name, metric, opts}) when is_list(opts), do: {name, metric, Map.new(opts)}

  @doc false
  def __handle__(metric_name, measurements, _metadata, {metric, opts}) do
    with {true, data} <- Process.get(__MODULE__),
         %{^metric => duration} <- measurements do
      current = System.monotonic_time(:millisecond)

      Process.put(
        __MODULE__,
        {true, [{metric_name, metric, duration, current, opts} | data]}
      )
    end

    :ok
  end

  defp timings(conn, start) do
    case Process.get(__MODULE__) do
      {true, measurements} ->
        value =
          measurements
          |> Enum.reverse()
          |> Enum.map_join(",", &encode(&1, start))

        put_resp_header(conn, "server-timing", value)

      _ ->
        conn
    end
  end

  defp encode({metric_name, metric, measurement, timestamp, opts}, start) do
    name = Map.get_lazy(opts, :name, fn -> "#{Enum.join(metric_name, ".")}.#{metric}" end)

    data = [
      {"dur", System.convert_time_unit(measurement, :native, :millisecond)},
      {"total", System.convert_time_unit(timestamp - start, :native, :millisecond)},
      {"desc", Map.get(opts, :description)}
    ]

    IO.iodata_to_binary([name, ?; | build(data)])
  end

  defp build([]), do: []
  defp build([{_name, nil} | rest]), do: build(rest)
  defp build([{name, value}]), do: [name, ?=, to_string(value)]
  defp build([{name, value} | rest]), do: [name, ?=, to_string(value), ?; | build(rest)]
end
