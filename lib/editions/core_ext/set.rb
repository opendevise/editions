require 'set' unless defined? Set
class Set
  def * separator = $,
    to_a * separator
  end unless respond_to? :*

  alias :concat :merge unless respond_to? :concat
end
