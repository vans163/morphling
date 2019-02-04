defmodule Morphling do
    def encode_rpc_navigate(path, title\\nil) do
        payload = """
            var path = "#{path}";
            if (location.pathname != path) {
                var title = #{if !title, do: "undefined", else: "\"#{title}\""};
                history.pushState(undefined, title, path);
            }
        """
        JSX.encode!(%{method: "morphling_eval", payload: payload})
    end
    def encode_rpc_set_cookie(k, v, opts) do
        opts = Enum.reduce(opts, "", fn({k,v},a)-> a<>"#{k}=#{v}; " end)
        payload = """
            document.cookie = "#{k}=#{v}; #{opts}"; 
        """
        JSX.encode!(%{method: "morphling_eval", payload: payload})
    end

    def encode_dom_diff(dom) do
        JSX.encode!(%{method: "morphling_dom_diff", payload: dom})
    end
    def encode_rpc(rpc_method, payload) do
        JSX.encode!(%{method: "morphling_rpc", rpc_method: rpc_method, payload: payload})
    end
    def encode_eval(payload) do
        JSX.encode!(%{method: "morphling_eval", payload: payload})
    end

    #Morphling.diff_dom("text", "text1")
    def diff_dom(old_dom, new_dom) when old_dom == new_dom, do: [%{t: :eq, op: 0, p: 0, s: byte_size(new_dom)}]
    def diff_dom("", new_dom), do: [%{t: :ins, b: new_dom, p: 0, s: byte_size(new_dom)}]
    def diff_dom(_, ""), do: [%{t: :ins, b: "", p: 0, s: 0}]
    def diff_dom(old_dom, new_dom) do
        fn_chunk = fn(bin,parts)->
            size = byte_size(bin)
            segment_size = div(size, parts)+1 #+1 account for 21.2 segment to be 22 otherwise we can be off by 100+ bytes
            {chunks,_} = Enum.reduce_while(0..(parts*2), {[], 0}, fn(_,{a,idx})->
                #piece = String.slice(bin, 0, segment_size)
                to_take = min(byte_size(bin)-idx, segment_size)
                piece = :erlang.binary_part(bin, idx, to_take)
                case piece do
                    "" -> {:halt, {a,bin}}
                    _ ->
                        a = a ++ [%{old_pos: idx, size: to_take, binary: piece}]
                        {:cont, {a, idx+to_take}}
                end
            end)
            chunks
        end

        #ts = :os.system_time(1000)
        parts = min(100, byte_size(old_dom))
        old_chunks = fn_chunk.(old_dom, parts)

        new_dom_size = byte_size(new_dom)
        #IO.inspect {1, :os.system_time(1000) - ts}

        #ts = :os.system_time(1000)
        old_chunks = Enum.reduce(old_chunks, [], fn(chunk, acc)->
            last_chunk = List.last(acc)
            match = cond do
                !last_chunk -> :binary.match(new_dom, chunk.binary)
                true -> :binary.match(new_dom, chunk.binary, [{:scope, {last_chunk.pos+last_chunk.size, new_dom_size-(last_chunk.pos+last_chunk.size)}}])
            end
            #IO.inspect match
            cond do
                match == :nomatch -> acc
                true ->
                    {pos, size} = match
                    #IO.inspect {:lc, last_chunk}
                    cond do
                        !last_chunk -> acc ++ [Map.merge(chunk, %{pos: pos})]
                        (last_chunk.pos + last_chunk.size) == pos ->
                            {_, acc} = List.pop_at(acc, -1)
                            acc ++ [Map.merge(chunk, %{old_pos: last_chunk.old_pos, pos: last_chunk.pos, size: last_chunk.size+size})]
                        pos < (last_chunk.pos + last_chunk.size) -> acc
                        true -> acc ++ [Map.merge(chunk, %{pos: pos})]
                    end
            end
        end)
        #IO.inspect {2, :os.system_time(1000) - ts}
        #IO.inspect old_chunks

        #ts = :os.system_time(1000)
        {final_diff, _, left_dom} = Enum.reduce(old_chunks, {[], 0, new_dom}, fn(%{old_pos: opos, pos: pos, size: size}, {acc, coverage_idx, new_dom})->
            cond do
                coverage_idx == pos ->
                    #IO.inspect {1, String.slice(new_dom, size, new_dom_size), pos+size}
                    {acc ++ [%{t: :eq, op: opos, p: pos, s: size}], pos+size, String.slice(new_dom, size, new_dom_size)}

                true ->
                    size_to_cover = pos - coverage_idx
                    #IO.inspect {2, String.slice(new_dom, size_to_cover, new_dom_size), size_to_cover, size, size_to_cover+size}
                    bin = String.slice(new_dom, 0, size_to_cover)
                    new_dom = String.slice(new_dom, size_to_cover, new_dom_size)
                    acc = acc ++ [%{t: :ins, p: pos-size_to_cover, s: size_to_cover, b: bin}]
                    {acc ++ [%{t: :eq, op: opos, p: pos, s: size}], pos+size, String.slice(new_dom, size, new_dom_size)}
            end
        end)
        #IO.inspect {3, :os.system_time(1000) - ts}

        #IO.inspect left_dom
        if byte_size(left_dom) > 0 do
            last_chunk = List.last(final_diff)
            cond do
                !last_chunk -> final_diff ++ [%{t: :ins, p: 0, s: byte_size(left_dom), b: left_dom}]
                true ->
                    pos = last_chunk.p + last_chunk.s
                    final_diff ++ [%{t: :ins, p: pos, s: byte_size(left_dom), b: left_dom}]
            end
        else final_diff end
    end


    def create(func, state\\%{}, timeout\\120000) do
        :erlang.spawn(fn()->
            dom = func.(state)
            timer_ref = :erlang.send_after(timeout, self(), :kill_by_create_timeout)
            loop(%{func: func, state: state, timer_ref: timer_ref, dom: dom})
        end)
    end

    def create_persistence(dom, state\\%{}, timeout\\120000) do
        :erlang.spawn(fn()->
            timer_ref = :erlang.send_after(timeout, self(), :kill_by_create_timeout)
            loop(%{dom: dom, state: state, timer_ref: timer_ref})
        end)
    end

    def get_persistence(pid) do
        send(pid, {:get_persistence, self()})
        receive do
            {:persistence, dom, state} -> {dom, state}
        after
            5000 -> throw(:get_morphling_persistence_timeout)
        end
    end 

    def state(pid) do
        send(pid, {:state, self()})
        receive do
            {:morphling_state, state} -> state
        after
            5000 -> throw(:get_morphling_state_timeout)
        end
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
    def delete_nested_1(_state, _list) do
        throw(:delete_nested_1_not_implemented)
    end

    def kill(pid) do
        Process.exit(pid, :normal)
    end

    def loop(state) do
        receive do
            :kill_by_create_timeout -> Process.exit(self(), :normal)

            {:get_persistence, pid} -> 
                send(pid, {:persistence, state.dom, state.state})
                loop(state)

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
                    #diff = diff_dom_1(old_dom, state.dom)
                    #send(pid, {:dom_changed, state.dom, diff})
                    #loop(state)
                end
        end
    end
end