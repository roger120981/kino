defmodule Kino.ProcessTest do
  use ExUnit.Case, async: true

  describe "app_tree/2" do
    test "raises if there is no sup tree" do
      assert_raise ArgumentError,
                   "the provided application :stdlib does not have a supervision tree",
                   fn -> Kino.Process.app_tree(:stdlib) end
    end
  end

  describe "sup_tree/2" do
    test "should render ETS tables if ETS tables are present and option is enabled" do
      pid = start_supervised!(supervision_tree_with_ets_table())

      [
        {:ets_owner, _owner_pid, :worker, _},
        {:ets_heir, _heir_pid, :worker, _},
        {Agent, agent_pid, :worker, _}
      ] = Supervisor.which_children(pid)

      content = pid |> Kino.Process.sup_tree(render_ets_tables: true) |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(ets_owner):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(ets_heir):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 3(#{inspect(agent_pid)}):::worker"

      assert content =~
               "1(ets_owner):::worker -- owner --> 4[(\"`test_ets_table\n**_protected_**`\")]:::ets"

      assert content =~
               "4[(\"`test_ets_table\n**_protected_**`\")]:::ets -. heir .-> 2(ets_heir):::worker"

      content = :supervisor_parent |> Kino.Process.sup_tree(render_ets_tables: true) |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(ets_owner):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(ets_heir):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 3(#{inspect(agent_pid)}):::worker"

      assert content =~
               "1(ets_owner):::worker -- owner --> 4[(\"`test_ets_table\n**_protected_**`\")]:::ets"

      assert content =~
               "4[(\"`test_ets_table\n**_protected_**`\")]:::ets -. heir .-> 2(ets_heir):::worker"
    end

    test "should not render ETS tables if ETS tables are present but option is not enabled" do
      pid = start_supervised!(supervision_tree_with_ets_table())

      [
        {:ets_owner, _owner_pid, :worker, _},
        {:ets_heir, _heir_pid, :worker, _},
        {Agent, agent_pid, :worker, _}
      ] = Supervisor.which_children(pid)

      content = pid |> Kino.Process.sup_tree() |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(ets_owner):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(ets_heir):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 3(#{inspect(agent_pid)}):::worker"
      refute content =~ ":::ets"

      content = :supervisor_parent |> Kino.Process.sup_tree() |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(ets_owner):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(ets_heir):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 3(#{inspect(agent_pid)}):::worker"
      refute content =~ ":::ets"
    end

    test "shows supervision tree with children" do
      pid =
        start_supervised!(%{
          id: Supervisor,
          start:
            {Supervisor, :start_link,
             [
               [
                 {Agent, fn -> :ok end},
                 %{id: :child, start: {Agent, :start_link, [fn -> :ok end, [name: :agent_child]]}}
               ],
               [name: :supervisor_parent, strategy: :one_for_one]
             ]},
          restart: :temporary
        })

      [_, {_, agent, _, _}] = Supervisor.which_children(pid)

      content = Kino.Process.sup_tree(pid) |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(agent_child):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(#{inspect(agent)}):::worker"

      content = Kino.Process.sup_tree(:supervisor_parent) |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(agent_child):::worker"
      assert content =~ "0(supervisor_parent):::root ---> 2(#{inspect(agent)}):::worker"
    end

    test "shows supervision tree with children alongside non-started children" do
      pid =
        start_supervised!(%{
          id: Supervisor,
          start:
            {Supervisor, :start_link,
             [
               [
                 {Agent, fn -> :ok end},
                 %{id: :not_started, start: {Function, :identity, [:ignore]}}
               ],
               [name: :supervisor_parent, strategy: :one_for_one]
             ]},
          restart: :temporary
        })

      [{:not_started, :undefined, _, _}, {_, agent, _, _}] = Supervisor.which_children(pid)

      content = Kino.Process.sup_tree(pid) |> mermaid()
      assert content =~ "0(supervisor_parent):::root ---> 1(id: :not_started):::notstarted"
      assert content =~ "0(supervisor_parent):::root ---> 2(#{inspect(agent)}):::worker"
    end

    test "raises if supervisor does not exist" do
      assert_raise ArgumentError,
                   ~r/the provided identifier :not_a_valid_supervisor does not reference a running process/,
                   fn -> Kino.Process.sup_tree(:not_a_valid_supervisor) end
    end
  end

  defp mermaid(%Kino.JS{ref: ref}) do
    send(Kino.JS.DataStore, {:connect, self(), %{origin: "client:#{inspect(self())}", ref: ref}})
    assert_receive {:connect_reply, data, %{ref: ^ref}}

    data
  end

  defp supervision_tree_with_ets_table do
    %{
      id: Supervisor,
      start:
        {Supervisor, :start_link,
         [
           [
             {Agent, fn -> :ok end},
             %{
               id: :ets_heir,
               start: {Agent, :start_link, [fn -> :ok end, [name: :ets_heir]]}
             },
             %{
               id: :ets_owner,
               start:
                 {Agent, :start_link,
                  [
                    fn ->
                      heir_pid = Process.whereis(:ets_heir)

                      :ets.new(
                        :test_ets_table,
                        [:set, :protected, :named_table, {:heir, heir_pid, nil}]
                      )
                    end,
                    [name: :ets_owner]
                  ]}
             }
           ],
           [name: :supervisor_parent, strategy: :one_for_one]
         ]},
      restart: :temporary
    }
  end
end
