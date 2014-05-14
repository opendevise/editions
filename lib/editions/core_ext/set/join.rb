class Set
  def join separator = $,
    to_a * separator
  end unless respond_to? :join

  alias :* :join unless respond_to? :*
end
