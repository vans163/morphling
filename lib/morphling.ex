defmodule Morphling do
    def loop(state) do
        receive do
            :kill_by_create_timeout -> Process.exit(self(), :normal)

            {:state, pid} -> 
                send(pid, {:morphling_state, state.state})
                loop(state)

            {:morph, list} ->
                state = if state[:timer_ref] != nil do 
                    :erlang.cancel_timer(state.timer_ref)
                    Map.delete(state, :timer_ref)
                else state end

                m_state = Enum.reduce(list, state.state, fn
                    ({:merge_nested, map}, a)-> merge_nested_1(a, map)
                    ({:delete_nested, list}, a)-> delete_nested_1(a, list)
                end)

                #new_dom = state.func.(m_state)
                #if state.dom != new_dom, do: send(state.pid, {:dom_changed, new_dom})

                loop(%{state|state: m_state, dom: state.func.(m_state)})

            {:diff_dom, pid, old_dom} ->
                if old_dom == state.dom do
                    send(pid, :no_diff)
                    loop(state)
                else
                    diff = diff_dom_1(old_dom, state.dom)
                    send(pid, {:dom_changed, state.dom, diff})
                    loop(state)
                end
        end
    end

    def encode_dom_diff(dom) do
        JSX.encode!(%{method: "morphling_dom_diff", payload: dom})
    end

    def create(func, state\\%{}, timeout\\120000) do
        :erlang.spawn(fn()->
            dom = func.(state)
            timer_ref = :erlang.send_after(timeout, self(), :kill_by_create_timeout)
            loop(%{func: func, state: state, timer_ref: timer_ref, dom: dom})
        end)
    end

    def state(pid) do
        send(pid, {:state, self()})
        receive do
            {:morphling_state, state} -> state
        after
            5000 -> throw(:get_morphling_state_timeout)
        end
    end 

    def diff_dom(pid, old_dom) do
        send(pid, {:diff_dom, self(), old_dom})
        receive do
            :no_diff -> {old_dom, []}
            {:dom_changed, new_dom, diff} -> {new_dom, diff}
        end
    end 
    def diff_dom_1(old_dom, dom) do
        """
        old_size = byte_size(old_dom)
        cs = div(old_size, 100)
        rem_size = rem(old_size, 100)
        chunks = List.duplicate(cs, 99) ++ [cs+rem_size]

        Enum.reduce(chunks, {[], 0, dom}, fn(size,{a,old_offset,new_dom})->
            old_slice = binary_part(old_dom, old_offset, size)
            new_match = :binary.match(dom, old_slice)

            cond do
                elem(new_match,0) == 0 ->
                    <<_::binary-size(size), rest::binary>> = dom

                    old_offset = old_offset + size
                    {a}

                new_match == :nomatch ->

            end
        end)

        old_slice = binary_part(old_dom, pos, len)

        old_dom, 10 slices
        old_dom, dom
        dom -- slices

        1..10
        """
        dom
    end

    def merge_nested(pid, map) do
        send(pid, {:morph, [{:merge_nested, map}]})
    end
    def merge_nested_1(left, right) do
        nested_resolve = fn(_, left, right)->
            case {is_map(left), is_map(right)} do
                {true, true} -> merge_nested_1(left, right)
                _ -> right
            end
        end
        Map.merge(left, right, nested_resolve)
    end

    def delete_nested(pid, list) do
        send(pid, {:morph, [{:delete_nested, list}]})
    end
    def delete_nested_1(state, list) do
        throw(:delete_nested_1_not_implemented)
    end

    def kill(pid) do
        Process.exit(pid, :normal)
    end
end