defmodule PronotexWeb.GradeTrendChart do
  use Phoenix.Component

  attr :points, :list, required: true
  attr :class_points, :list, default: []

  def chart(assigns) do
    domain = assigns.points ++ assigns.class_points
    coordinates = coordinates(assigns.points, domain)
    class_coordinates = coordinates(assigns.class_points, domain)

    assigns =
      assign(assigns,
        path: path(coordinates),
        markers: markers(assigns.points, coordinates),
        class_path: path(class_coordinates),
        class_markers: markers(assigns.class_points, class_coordinates)
      )

    ~H"""
    <div :if={@points != [] or @class_points != []} id="overall-trend" class="overall-trend">
      <svg
        viewBox="0 0 600 140"
        preserveAspectRatio="none"
        role="img"
        aria-label="Évolution des moyennes générales de l’élève et de la classe sur la période ; classe en gris clair"
      >
        <g class="class-average-trend" stroke="#d1d5db" fill="#d1d5db" opacity="0.5">
          <title>Moyenne générale de la classe</title>
          <path
            d={@class_path}
            fill="none"
            stroke-width="3"
            stroke-linecap="round"
            stroke-linejoin="round"
            vector-effect="non-scaling-stroke"
          />
        </g>
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
      <.marker :for={point <- @class_markers} point={point} prefix="class-trend" class?={true} />
      <.marker :for={point <- @markers} point={point} prefix="trend" class?={false} />
    </div>
    """
  end

  attr :point, :map, required: true
  attr :prefix, :string, required: true
  attr :class?, :boolean, required: true

  defp marker(assigns) do
    ~H"""
    <button
      id={"#{@prefix}-point-#{@point.index}"}
      type="button"
      phx-click={Phoenix.LiveView.JS.focus(to: "##{@prefix}-point-#{@point.index}")}
      class={["trend-point", @class? && "trend-point-class", @point.last? && "trend-point-last"]}
      style={"left: #{@point.x}%; top: #{@point.y}%"}
      aria-label={"#{@point.date} : #{if @class?, do: "moyenne de classe", else: "moyenne officielle"} #{@point.value} sur 20"}
      aria-describedby={"#{@prefix}-tooltip-#{@point.index}"}
      data-placement={@point.placement}
    >
      <span class="trend-point-dot" aria-hidden="true"></span>
      <span id={"#{@prefix}-tooltip-#{@point.index}"} role="tooltip" class="trend-tooltip">
        <span>{@point.date}</span>
        <strong>{@point.value} / 20</strong>
      </span>
    </button>
    """
  end

  defp markers(points, coordinates) do
    Enum.zip(points, coordinates)
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
  end

  defp coordinates([], _domain), do: []

  defp coordinates(points, domain) do
    {first, _} = Enum.min_by(domain, fn {date, _} -> elapsed(date, elem(hd(domain), 0)) end)
    {last, _} = Enum.max_by(domain, fn {date, _} -> elapsed(date, first) end)
    duration = max(elapsed(last, first), 1)
    lower_bound = domain |> Enum.map(&elem(&1, 1)) |> Enum.min()
    score_range = max(20 - lower_bound, 1)

    Enum.map(points, fn {date, value} ->
      {Float.round(12 + elapsed(date, first) / duration * 576, 2),
       Float.round(128 - (value - lower_bound) / score_range * 116, 2)}
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
