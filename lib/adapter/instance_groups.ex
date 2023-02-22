defmodule Cluster.Strategy.Adapter.InstanceGroups do
  @moduledoc """
  Find all the instances available in a project

  """
  @behaviour Cluster.Strategy.Adapter
  alias GoogleApi.Compute.V1.Connection
  alias GoogleApi.Compute.V1.Api.Instances

  alias GoogleApi.Compute.V1.Model.{
    Instance,
    InstanceAggregatedList,
    InstancesScopedList
  }

  require Logger

  @doc """
  return a list of compute instances, available in the specified project
  """
  def get_nodes(release_name, config) do
    _ =
      get_instance_group_nodes(
        release_name,
        config[:project]
      )
  end

  defp get_instance_group_nodes(
         release_name,
         project
       ) do
    get_access_token()
    |> Connection.new()
    |> Instances.compute_instances_aggregated_list(project)
    |> iterate_instance_items(release_name, project)
  end

  defp get_access_token() do
    {:ok, response} = Goth.Token.for_scope("https://www.googleapis.com/auth/cloud-platform")

    response.token
  end

  defp iterate_instance_items(
         {:ok, %InstanceAggregatedList{items: items}},
         release_name,
         project
       ) do
    nodes =
      items
      |> Enum.filter(&filter_by_warnings/1)
      |> Enum.map(&build_dns_name(&1, release_name, project))
      |> List.flatten()

    {:ok, nodes}
  end

  defp iterate_instance_items(error, _release_name, _project) do
    Logger.error(inspect(error))
    {:error, error}
  end

  defp build_dns_name(
         {zone, %InstancesScopedList{instances: instances}},
         release_name,
         project
       ) do
    %{"regions" => zone} = Regex.named_captures(~r/.*\/(?<regions>.*)$/, zone)

    instances
    |> Enum.filter(&filter_by_running_instances/1)
    |> Enum.map(fn %Instance{name: name} ->
      :"#{release_name}@#{name}.#{zone}.c.#{project}.internal"
    end)
  end

  defp filter_by_warnings({_zone, %{warning: nil}}), do: true
  defp filter_by_warnings(_), do: false

  defp filter_by_running_instances(%Instance{status: "RUNNING"}), do: true
  defp filter_by_running_instances(_), do: false
end
