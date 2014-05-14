class Set
  alias :concat :merge unless respond_to? :concat
end
