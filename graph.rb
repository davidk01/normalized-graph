require 'digest'

# rubocop:disable Metrics/AbcSize

# Where we store the mapping from hashes to the actual nodes
class ContentStore
  # Types for atomic values
  ATOMIC_TYPES = [Numeric, Symbol, String, FalseClass, TrueClass].freeze

  # We only allow hashes and arrays as compound values. To store any other
  # type of value the user must serialize their value to one of these types
  COMPOUND_TYPES = [H = Hash, A = Array].freeze

  attr_reader :store

  # We store everything inside a hash that lives in memory
  def initialize
    @store = {}
  end

  # Generate the digest for the value, store it, and return the digest
  def add(value)
    normalized_value = normalize(value)
    key = hashify(normalized_value)
    @store[key] = normalized_value
    key
  end

  # Are we dealing with an atomic value?
  def self.atomic?(value)
    value_class = value.class
    ATOMIC_TYPES.any? { |t| t == value_class }
  end

  # We need to normalize compound values before storing them
  def normalize(value)
    case value
    when *ATOMIC_TYPES
      # Atomic values normalize to themselves
      value
    when *COMPOUND_TYPES
      # For compound values we recursively normalize and add the entries
      case value
      when A
        # Add each entry to the store
        value.map { |v| add(v) }
      when H
        # Sort the keys, normalize, add the values to the store
        zipped_keys = value.keys.zip(value.keys.map(&:to_sym)).sort_by { |(_, b)| b }
        zipped_keys.each_with_object({}) do |(original_key, symbol_key), memo|
          memo[symbol_key] = add(value[original_key])
        end
      else
        # This should never happen
        raise StandardError, "Unhandled case for compound value"
      end
    else
      raise StandardError, "Unknown value type. Can not normalize #{value.class}"
    end
  end

  # Hashification of values. This is what makes things content addressable
  def hashify(normalized_value)
    digest = Digest::SHA256.new
    # Add the prefix to distinguish between the different types. Otherwise,
    # 1 and '1', or {} and [] map to the same values which is not what we
    # want
    digest.update normalized_value.class.to_s
    # Now digest the value
    case normalized_value
    when *ATOMIC_TYPES
      # Atomic values are easy, just convert to string and digest
      digest.update normalized_value.to_s
    when *COMPOUND_TYPES
      # Compound values aren't much harder, just iterate through each
      # key/value pair and digest them
      normalized_value.each do |k, v|
        digest.update k.to_s
        digest.update v.to_s
      end
    else
      # Should never happen because 'normalize' should already rule out unknown types
      raise StandardError, "Can not hashify unknown type #{normalize_value.class}"
    end
    # Return the final digest as a symbol
    digest.hexdigest.to_sym
  end
end
