defmodule LiveTrivia.Benchmark.Telemetry do
  use GenServer

  require Logger

  @enabled_key {__MODULE__, :enabled?}
  @events [
    [:live_trivia, :typing_channel, :typing],
    [:live_trivia, :synthetic_benchmark, :client_summary]
  ]
  @log_interval_ms 5_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def enabled? do
    :persistent_term.get(@enabled_key, false)
  end

  @impl true
  def init(_opts) do
    :persistent_term.put(@enabled_key, true)
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, self())
    schedule_log()

    reductions = total_reductions()
    system_sample = system_sample()

    {:ok,
     %{
       label: System.get_env("LIVE_TRIVIA_BENCHMARK_LABEL", "default"),
       interval_started_at: System.monotonic_time(:millisecond),
       interval: new_interval(),
       aggregate: new_aggregate(reductions, system_sample),
       reductions: reductions,
       system_sample: system_sample
     }}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(__MODULE__)
    :persistent_term.put(@enabled_key, false)
    :ok
  end

  def handle_event([:live_trivia, :typing_channel, :typing], measurements, metadata, pid) do
    send(pid, {:typing_event, measurements, metadata})
  end

  def handle_event(
        [:live_trivia, :synthetic_benchmark, :client_summary],
        measurements,
        metadata,
        pid
      ) do
    send(pid, {:client_summary, measurements, metadata})
  end

  @impl true
  def handle_info({:typing_event, measurements, _metadata}, state) do
    duration_us =
      measurements
      |> Map.get(:duration, 0)
      |> System.convert_time_unit(:native, :microsecond)

    event = %{
      count: Map.get(measurements, :count, 1),
      bytes: Map.get(measurements, :payload_bytes, 0),
      duration_us: duration_us
    }

    {:noreply, %{state | interval: record_typing_event(state.interval, event)}}
  end

  def handle_info({:client_summary, measurements, metadata}, state) do
    state = fold_interval(state)
    summary = Map.merge(metadata, measurements)

    log_client_summary(state.label, summary)
    log_attempt_summary(state.label, summary, state.aggregate)

    {:noreply,
     %{
       state
       | aggregate: new_aggregate(state.reductions, state.system_sample),
         interval_started_at: System.monotonic_time(:millisecond),
         interval: new_interval()
     }}
  end

  def handle_info(:log_snapshot, state) do
    state = fold_interval(state)
    log_snapshot(state.label, state.last_snapshot)
    schedule_log()

    {:noreply,
     %{state | interval_started_at: System.monotonic_time(:millisecond), interval: new_interval()}}
  end

  defp record_typing_event(interval, event) do
    %{
      interval
      | typing_count: interval.typing_count + event.count,
        typing_bytes: interval.typing_bytes + event.bytes,
        typing_duration_us: [event.duration_us | interval.typing_duration_us]
    }
  end

  defp fold_interval(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_seconds = max((now - state.interval_started_at) / 1000, 0.001)
    current_reductions = total_reductions()
    reductions_delta = current_reductions - state.reductions
    current_sample = system_sample()
    cpu = cpu_delta(state.system_sample, current_sample)
    durations = state.interval.typing_duration_us
    sorted_durations = Enum.sort(durations)
    typing_count = state.interval.typing_count
    typing_bytes = state.interval.typing_bytes

    snapshot = %{
      elapsed_seconds: elapsed_seconds,
      typing_count: typing_count,
      typing_per_sec: safe_div(typing_count, elapsed_seconds),
      typing_bytes: typing_bytes,
      avg_payload_bytes: safe_div(typing_bytes, typing_count),
      avg_handle_us: average(durations),
      p95_handle_us: percentile(sorted_durations, 0.95),
      max_handle_us: Enum.max(durations, fn -> 0 end),
      reductions_delta: reductions_delta,
      reductions_per_sec: safe_div(reductions_delta, elapsed_seconds),
      beam_memory_kb: memory_kb(),
      rss_kb: current_sample.rss_kb,
      cpu_total_pct: cpu.total_pct,
      cpu_core_pct: cpu.core_pct,
      process_count: :erlang.system_info(:process_count),
      run_queue: :erlang.statistics(:run_queue),
      collector_queue: collector_queue_len()
    }

    state
    |> Map.merge(%{
      aggregate: record_snapshot(state.aggregate, snapshot),
      reductions: current_reductions,
      system_sample: current_sample
    })
    |> Map.put(:last_snapshot, snapshot)
  end

  defp record_snapshot(aggregate, snapshot) do
    %{
      aggregate
      | elapsed_seconds: aggregate.elapsed_seconds + snapshot.elapsed_seconds,
        typing_count: aggregate.typing_count + snapshot.typing_count,
        typing_bytes: aggregate.typing_bytes + snapshot.typing_bytes,
        reductions_delta: aggregate.reductions_delta + snapshot.reductions_delta,
        handle_durations_us:
          add_non_empty(
            aggregate.handle_durations_us,
            snapshot,
            :avg_handle_us,
            snapshot.typing_count
          ),
        cpu_total_samples: add_known_sample(aggregate.cpu_total_samples, snapshot.cpu_total_pct),
        cpu_core_samples: add_known_sample(aggregate.cpu_core_samples, snapshot.cpu_core_pct),
        max_cpu_total_pct: max_known(aggregate.max_cpu_total_pct, snapshot.cpu_total_pct),
        max_cpu_core_pct: max_known(aggregate.max_cpu_core_pct, snapshot.cpu_core_pct),
        max_rss_kb: max_known(aggregate.max_rss_kb, snapshot.rss_kb),
        max_beam_memory_kb: max(aggregate.max_beam_memory_kb, snapshot.beam_memory_kb),
        max_run_queue: max(aggregate.max_run_queue, snapshot.run_queue),
        max_collector_queue: max(aggregate.max_collector_queue, snapshot.collector_queue),
        snapshot_count: aggregate.snapshot_count + 1
    }
  end

  defp log_snapshot(label, snapshot) do
    Logger.info(fn ->
      [
        "benchmark snapshot ",
        "label=#{label} ",
        "typing_count=#{snapshot.typing_count} ",
        "typing_per_sec=#{round_float(snapshot.typing_per_sec)} ",
        "typing_bytes=#{snapshot.typing_bytes} ",
        "avg_payload_bytes=#{round_float(snapshot.avg_payload_bytes)} ",
        "avg_handle_us=#{round_float(snapshot.avg_handle_us)} ",
        "p95_handle_us=#{round_float(snapshot.p95_handle_us)} ",
        "max_handle_us=#{round_float(snapshot.max_handle_us)} ",
        "reductions_delta=#{snapshot.reductions_delta} ",
        "reductions_per_sec=#{round_float(snapshot.reductions_per_sec)} ",
        "beam_memory_kb=#{snapshot.beam_memory_kb} ",
        "rss_kb=#{format_value(snapshot.rss_kb)} ",
        "cpu_total_pct=#{format_value(snapshot.cpu_total_pct)} ",
        "cpu_core_pct=#{format_value(snapshot.cpu_core_pct)} ",
        "process_count=#{snapshot.process_count} ",
        "run_queue=#{snapshot.run_queue} ",
        "collector_queue=#{snapshot.collector_queue}"
      ]
    end)
  end

  defp log_client_summary(label, summary) do
    Logger.info(fn ->
      [
        "synthetic client summary ",
        "label=#{label} ",
        "room_id=#{summary[:room_id]} ",
        "samples=#{summary[:samples]} ",
        "avg_ms=#{summary[:avg_ms]} ",
        "p50_ms=#{summary[:p50_ms]} ",
        "p95_ms=#{summary[:p95_ms]} ",
        "p99_ms=#{summary[:p99_ms]} ",
        "max_ms=#{summary[:max_ms]} ",
        "receive_p95_ms=#{summary[:receive_p95_ms]} ",
        "receive_p99_ms=#{summary[:receive_p99_ms]} ",
        "dom_p95_ms=#{summary[:dom_p95_ms]} ",
        "dom_p99_ms=#{summary[:dom_p99_ms]} ",
        "duration_ms=#{summary[:duration_ms]}"
      ]
    end)
  end

  defp log_attempt_summary(label, client_summary, aggregate) do
    Logger.info(fn ->
      [
        "benchmark attempt summary ",
        "label=#{label} ",
        "room_id=#{client_summary[:room_id]} ",
        "client_samples=#{client_summary[:samples]} ",
        "client_avg_ms=#{client_summary[:avg_ms]} ",
        "client_p95_ms=#{client_summary[:p95_ms]} ",
        "client_p99_ms=#{client_summary[:p99_ms]} ",
        "client_max_ms=#{client_summary[:max_ms]} ",
        "receive_p95_ms=#{client_summary[:receive_p95_ms]} ",
        "receive_p99_ms=#{client_summary[:receive_p99_ms]} ",
        "dom_p95_ms=#{client_summary[:dom_p95_ms]} ",
        "dom_p99_ms=#{client_summary[:dom_p99_ms]} ",
        "duration_ms=#{client_summary[:duration_ms]} ",
        "typing_count=#{aggregate.typing_count} ",
        "typing_per_sec=#{round_float(safe_div(aggregate.typing_count, aggregate.elapsed_seconds))} ",
        "client_window_typing_per_sec=#{round_float(client_window_typing_per_sec(aggregate, client_summary))} ",
        "typing_bytes=#{aggregate.typing_bytes} ",
        "avg_payload_bytes=#{round_float(safe_div(aggregate.typing_bytes, aggregate.typing_count))} ",
        "avg_handle_us=#{round_float(weighted_average(aggregate.handle_durations_us))} ",
        "reductions_delta=#{aggregate.reductions_delta} ",
        "reductions_per_sec=#{round_float(safe_div(aggregate.reductions_delta, aggregate.elapsed_seconds))} ",
        "avg_cpu_total_pct=#{format_value(average(aggregate.cpu_total_samples))} ",
        "max_cpu_total_pct=#{format_value(aggregate.max_cpu_total_pct)} ",
        "avg_cpu_core_pct=#{format_value(average(aggregate.cpu_core_samples))} ",
        "max_cpu_core_pct=#{format_value(aggregate.max_cpu_core_pct)} ",
        "max_rss_kb=#{format_value(aggregate.max_rss_kb)} ",
        "max_beam_memory_kb=#{aggregate.max_beam_memory_kb} ",
        "max_run_queue=#{aggregate.max_run_queue} ",
        "max_collector_queue=#{aggregate.max_collector_queue} ",
        "snapshots=#{aggregate.snapshot_count}"
      ]
    end)
  end

  defp client_window_typing_per_sec(aggregate, client_summary) do
    duration_ms = Map.get(client_summary, :duration_ms, 0)
    safe_div(aggregate.typing_count, safe_div(duration_ms, 1000))
  end

  defp schedule_log do
    Process.send_after(self(), :log_snapshot, @log_interval_ms)
  end

  defp new_interval do
    %{typing_count: 0, typing_bytes: 0, typing_duration_us: []}
  end

  defp new_aggregate(_reductions, _sample) do
    %{
      elapsed_seconds: 0.0,
      typing_count: 0,
      typing_bytes: 0,
      reductions_delta: 0,
      handle_durations_us: [],
      cpu_total_samples: [],
      cpu_core_samples: [],
      max_cpu_total_pct: nil,
      max_cpu_core_pct: nil,
      max_rss_kb: nil,
      max_beam_memory_kb: memory_kb(),
      max_run_queue: 0,
      max_collector_queue: 0,
      snapshot_count: 0
    }
  end

  defp total_reductions do
    :erlang.statistics(:reductions) |> elem(0)
  end

  defp average([]), do: 0
  defp average(values), do: Enum.sum(values) / length(values)

  defp weighted_average([]), do: 0

  defp weighted_average(weighted_values) do
    {total, count} =
      Enum.reduce(weighted_values, {0, 0}, fn {value, weight}, {total, count} ->
        {total + value * weight, count + weight}
      end)

    safe_div(total, count)
  end

  defp safe_div(_numerator, 0), do: 0
  defp safe_div(numerator, denominator), do: numerator / denominator

  defp percentile([], _percentile), do: 0

  defp percentile(sorted_values, percentile) do
    index =
      sorted_values
      |> length()
      |> Kernel.*(percentile)
      |> Float.ceil()
      |> trunc()
      |> Kernel.-(1)
      |> max(0)
      |> min(length(sorted_values) - 1)

    Enum.at(sorted_values, index)
  end

  defp round_float(value) when is_number(value), do: Float.round(value / 1, 2)
  defp round_float(value), do: value

  defp format_value(nil), do: "unknown"
  defp format_value(value) when is_float(value), do: Float.round(value, 2)
  defp format_value(value), do: value

  defp add_non_empty(values, %{typing_count: 0}, _key, _weight), do: values

  defp add_non_empty(values, snapshot, key, weight),
    do: [{Map.fetch!(snapshot, key), weight} | values]

  defp add_known_sample(samples, nil), do: samples
  defp add_known_sample(samples, value), do: [value | samples]

  defp max_known(nil, nil), do: nil
  defp max_known(current, nil), do: current
  defp max_known(nil, value), do: value
  defp max_known(current, value), do: max(current, value)

  defp memory_kb do
    :erlang.memory(:total) |> div(1024)
  end

  defp collector_queue_len do
    self()
    |> Process.info(:message_queue_len)
    |> case do
      {:message_queue_len, length} -> length
      nil -> 0
    end
  end

  defp system_sample do
    %{
      proc_ticks: proc_cpu_ticks(),
      total_ticks: total_cpu_ticks(),
      rss_kb: rss_kb(),
      schedulers_online: :erlang.system_info(:schedulers_online)
    }
  end

  defp cpu_delta(%{proc_ticks: nil}, _current), do: %{total_pct: nil, core_pct: nil}
  defp cpu_delta(%{total_ticks: nil}, _current), do: %{total_pct: nil, core_pct: nil}
  defp cpu_delta(_previous, %{proc_ticks: nil}), do: %{total_pct: nil, core_pct: nil}
  defp cpu_delta(_previous, %{total_ticks: nil}), do: %{total_pct: nil, core_pct: nil}

  defp cpu_delta(previous, current) do
    proc_delta = current.proc_ticks - previous.proc_ticks
    total_delta = current.total_ticks - previous.total_ticks

    total_pct = if total_delta > 0, do: proc_delta / total_delta * 100, else: 0.0

    %{
      total_pct: total_pct,
      core_pct: total_pct * current.schedulers_online
    }
  end

  defp proc_cpu_ticks do
    with {:ok, stat} <- File.read("/proc/self/stat"),
         [_pid_and_comm, fields] <- :binary.split(stat, ") "),
         values <- String.split(fields),
         {utime, ""} <- values |> Enum.at(11, "0") |> Integer.parse(),
         {stime, ""} <- values |> Enum.at(12, "0") |> Integer.parse() do
      utime + stime
    else
      _error -> nil
    end
  end

  defp total_cpu_ticks do
    with {:ok, stat} <- File.read("/proc/stat"),
         [cpu_line | _rest] <- String.split(stat, "\n", parts: 2),
         [_cpu | values] <- String.split(cpu_line),
         ticks when ticks != [] <- Enum.map(values, &parse_int/1) do
      Enum.sum(ticks)
    else
      _error -> nil
    end
  end

  defp rss_kb do
    with {:ok, status} <- File.read("/proc/self/status"),
         line when is_binary(line) <- find_status_line(status, "VmRSS:"),
         [value | _rest] <- Regex.run(~r/\d+/, line),
         {rss, ""} <- Integer.parse(value) do
      rss
    else
      _error -> nil
    end
  end

  defp find_status_line(status, prefix) do
    status
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, prefix))
  end

  defp parse_int(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> 0
    end
  end
end
