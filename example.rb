require './graph'
require 'json'

# rubocop:disable Metrics/AbcSize

# Escape the string so we can use it as a graphviz label
def graphviz_escape(str)
  ret = str.to_s.gsub('"', "\\\"")
  ret.gsub!(/([';<> {}])/, '\\\\\1')
  ret
end

# Value must be array otherwise we get into buggy situation
def graphviz_array_label(key, graph)
  indices = graph[key].each_with_index.map do |target, i|
    target_part = ''
    target_value = graph[target]
    if ContentStore.atomic?(target_value)
      target_part = graphviz_escape(target_value)
      target_part = target[0..5] if target_part.length > 80
    end
    if !target_part.empty?
      "{<f#{i}> #{i}|#{target_part}}"
    else
      "<f#{i}> #{i}"
    end
  end.join('|')
  "{#{key[0..5]}|{#{indices}}}"
end

# Value must be a hash map
def graphviz_hash_label(key, graph)
  hash_keys = graph[key].each_with_index.map do |(k, target), i|
    target_value = graph[target]
    value_part = ''
    if ContentStore.atomic?(target_value)
      value_part = graphviz_escape(target_value)
      value_part = target[0..5] if value_part.length > 80
    end
    key_part = "<f#{i}> #{graphviz_escape(k)}"
    if !value_part.empty?
      "{#{key_part}|#{value_part}}"
    else
      key_part
    end
  end.join('|')
  "{#{key[0..5]}|{#{hash_keys}}}"
end

def graphviz_atomic_node_label(key, value)
  escaped_value = graphviz_escape(value)
  escaped_value = '' if escaped_value.length > 80
  "{#{key[0..5]}|#{escaped_value}}"
end

# Generate the content for the node definition
def graphviz_node(key, label)
  "  \"#{key}\" [shape=record,label=\"#{label}\"];\n"
end

# Generate the content for the edge definition
def graphviz_edge(source, port, target, label)
  prefix = "\"#{source}\"" + (port ? ":#{port}" : '')
  suffix = label ? " [decorate=true,label=\"#{source[0..5]}:#{target[0..5]}:#{label}\"]" : ''
  "  #{prefix} -> \"#{target}\"#{suffix};\n"
end

# Traverse the graph and generate the dot specification
def graphviz(key, graph, max_depth, current_depth = 0, accumulator = "", done = {})
  return if current_depth > max_depth
  # Return if we have already traversed this node
  return if done[key]
  done[key] = true
  case value = graph[key]
  when *ContentStore::ATOMIC_TYPES
    # Nothing to do for atomic values other than add a node
    label = graphviz_atomic_node_label(key, value)
    accumulator << graphviz_node(key, label)
  when *ContentStore::COMPOUND_TYPES
    # For compound values we need to figure out if we are working with array or hash
    case value
    when ContentStore::A
      label = graphviz_array_label(key, graph)
      accumulator << graphviz_node(key, label)
      value.each_with_index do |target, index|
        next if ContentStore.atomic?(graph[target])
        port = "f#{index}"
        accumulator << graphviz_edge(key, port, target, index)
        graphviz(target, graph, max_depth, current_depth + 1, accumulator, done)
      end
    when ContentStore::H
      # Working with a hash so make the keys the values of the record
      label = graphviz_hash_label(key, graph)
      accumulator << graphviz_node(key, label)
      value.each_with_index do |(edge, target), index|
        # Skip the target if it is an atomic node because we will include it
        # in the source node label as another entry
        next if ContentStore.atomic?(graph[target])
        port = "f#{index}"
        accumulator << graphviz_edge(key, port, target, edge)
        graphviz(target, graph, max_depth, current_depth + 1, accumulator, done)
      end
    else
      raise StandardError, "Unknown compound type #{value.class}"
    end
  end
end

g = ContentStore.new
stack = g.add(JSON.parse(File.read('cloud-formation.json')))
store = g.store

# Convert the graph to graphviz dot for viewing. Each entry in the store
# becomes a node and each key/value pair becomes a directed edge going from the
# key to the value
dot = "digraph g {\n"
graphviz(stack, store, 10, 0, dot)
dot << "}"
puts dot
