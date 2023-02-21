defmodule Cluster.Strategy.Adapter.InstanceGroups do
  @moduledoc """
  Find all the instances available in a  managed instance group
  A managed instance group is a group of homogeneous instances based on an instance template.

  https://cloud.google.com/compute/docs/instance-groups/creating-groups-of-managed-instances

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
  return a list of compute instances, available in the specified topology
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
    conn = get_access_token() |> Connection.new()

    instances =
      Instances.compute_instances_aggregated_list(
        conn,
        project
      )

    case instances do
      {:ok, %InstanceAggregatedList{items: items}} ->
        nodes =
          items
          |> Enum.filter(fn
            {_zone, %{warning: nil}} -> true
            _ -> false
          end)
          |> Enum.map(fn {_zone, %InstancesScopedList{instances: instances}} ->
            instances
            |> Enum.filter(fn
              %Instance{status: "RUNNING"} -> true
              _ -> false
            end)
            |> Enum.map(fn %Instance{name: name, zone: zone} ->
              %{"zones" => zone} = Regex.named_captures(~r/.*\/(?<zones>.*)$/, zone)

              :"#{release_name}@#{name}.c.#{zone}.#{project}.internal"
            end)
          end)
          |> List.flatten()

        {:ok, nodes}

      e ->
        Logger.error(inspect(e))
        {:error, e}
    end
  end

  defp get_access_token() do
    {:ok, response} = Goth.Token.for_scope("https://www.googleapis.com/auth/cloud-platform")

    response.token
  end
end
