defmodule Plug.Telemetry.ServerTiming do
  @behaviour Plug

  @external_resource "README.md"
  @moduledoc File.read!("README.md")
             |> String.split(~r/<!--\s*(BEGIN|END)\s*-->/, parts: 3)
             |> Enum.at(1)

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
          {:telemetry.event_name(), measurement :: atom()}
          | {:telemetry.event_name(), measurement :: atom(), opts :: keyword() | map()}

  @doc """
  Define which events should be available within response headers.

  Tuple values are:

  1. List of atoms that is the name of the event that we should listen for.
  2. Atom that contains the name of the metric that should be recorded.
  3. Optionally keyword list or map with additional options. Currently
     supported options are:

     - `:name` - alternative name for the metric. By default it will be
       constructed by joining event name and name of metric with dots.
       Ex. for `{[:foo, :bar], :baz}` default metric name will be `foo.bar.baz`.
     - `:description` - string that will be set as `desc`.

  ## Example

  ```elixir
  #{inspect(__MODULE__)}.install([
    {[:phoenix, :endpoint, :stop], :duration, description: "Phoenix time"},
    {[:my_app, :repo, :query], :total_time, description: "DB request"}
  ])
  ```
  """
  @spec install(events()) :: :ok
  def install(events) do
    for event <- events,
        {metric_name, metric, opts} = normalise(event) do
      name = Map.get_lazy(opts, :name, fn -> "#{Enum.join(metric_name, ".")}.#{metric}" end)
      description = Map.get(opts, :description, "")

      :ok =
        :telemetry.attach(
          {__MODULE__, name},
          metric_name,
          &__MODULE__.__handle__/4,
          {metric, %{name: name, desc: description}}
        )
    end

    :ok
  end

  defp normalise({name, metric}), do: {name, metric, %{}}
  defp normalise({name, metric, opts}) when is_map(opts), do: {name, metric, opts}
  defp normalise({name, metric, opts}) when is_list(opts), do: {name, metric, Map.new(opts)}

  @doc false
  def __handle__(_metric_name, measurements, _metadata, {metric, opts}) do
    with {true, data} <- Process.get(__MODULE__),
         %{^metric => duration} <- measurements do
      current = System.monotonic_time(:millisecond)

      Process.put(
        __MODULE__,
        {true, [{duration, current, opts} | data]}
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

  defp encode({measurement, timestamp, opts}, start) do
    %{desc: desc, name: name} = opts
    data = [
      {"dur", System.convert_time_unit(measurement, :native, :millisecond)},
      {"total", System.convert_time_unit(timestamp - start, :native, :millisecond)},
      {"desc", desc}
    ]

    IO.iodata_to_binary([name, ?; | build(data)])
  end

  defp build([]), do: []
  defp build([{_name, nil} | rest]), do: build(rest)
  defp build([{name, value}]), do: [name, ?=, to_string(value)]
  defp build([{name, value} | rest]), do: [name, ?=, to_string(value), ?; | build(rest)]
end
