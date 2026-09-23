defmodule PronotexWeb.GradeTrendChart do
  use Phoenix.Component

  attr :points, :list, required: true

  def chart(assigns) do
    coordinates = coordinates(assigns.points)

    markers =
      Enum.zip(assigns.points, coordinates)
      |> Enum.with_index()
      |> Enum.map(fn {{{date, value}, {x, y}}, index} ->
        %{
          index: index,
          date: Calendar.strftime(date, "%d/%m/%Y"),
          value:
            value
            |> Kernel./(1)
            |> :erlang.float_to_binary(decimals: 2)
            |> String.replace(".", ","),
          x: x / 6,
          y: y / 1.4,
          last?: index == length(coordinates) - 1,
          placement:
            cond do
              x < 150 -> "start"
              x > 450 -> "end"
              true -> "middle"
            end
        }
      end)

    assigns = assign(assigns, path: path(coordinates), markers: markers)

    ~H"""
    <div :if={@points != []} id="overall-trend" class="overall-trend">
      <svg
        viewBox="0 0 600 140"
        preserveAspectRatio="none"
        role="img"
        aria-label="Évolution de la moyenne générale sur la période"
      >
        <path
          d={@path}
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
      <button
        :for={point <- @markers}
        id={"trend-point-#{point.index}"}
        type="button"
        phx-click={Phoenix.LiveView.JS.focus(to: "#trend-point-#{point.index}")}
        class={["trend-point", point.last? && "trend-point-last"]}
        style={"left: #{point.x}%; top: #{point.y}%"}
        aria-label={"#{point.date} : moyenne officielle #{point.value} sur 20"}
        aria-describedby={"trend-tooltip-#{point.index}"}
        data-placement={point.placement}
      >
        <span class="trend-point-dot" aria-hidden="true"></span>
        <span id={"trend-tooltip-#{point.index}"} role="tooltip" class="trend-tooltip">
          <span>{point.date}</span>
          <strong>{point.value} / 20</strong>
        </span>
      </button>
    </div>
    """
  end

  defp coordinates([]), do: []

  defp coordinates(points) do
    {first, _} = hd(points)
    {last, _} = List.last(points)
    duration = max(elapsed(last, first), 1)
    lower_bound = points |> Enum.map(&elem(&1, 1)) |> Enum.min() |> Kernel.-(2)

    Enum.map(points, fn {date, value} ->
      {Float.round(12 + elapsed(date, first) / duration * 576, 2),
       Float.round(128 - (value - lower_bound) / (20 - lower_bound) * 116, 2)}
    end)
  end

  defp elapsed(%DateTime{} = last, %DateTime{} = first),
    do: DateTime.diff(last, first, :microsecond)

  defp elapsed(%Date{} = last, %Date{} = first), do: Date.diff(last, first)

  defp path([]), do: ""

  defp path([{x, y} | rest]) do
    {segments, _} =
      Enum.map_reduce(rest, {x, y}, fn {next_x, next_y}, {previous_x, previous_y} ->
        middle = Float.round((previous_x + next_x) / 2, 2)
        {"C #{middle} #{previous_y}, #{middle} #{next_y}, #{next_x} #{next_y}", {next_x, next_y}}
      end)

    Enum.join(["M #{x} #{y}" | segments], " ")
  end
end
