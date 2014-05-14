class NilClass
  alias :nil_or_empty? :nil? unless respond_to? :nil_or_empty?
end

class String
  alias :nil_or_empty? :empty? unless respond_to? :nil_or_empty?
end

class Array
  alias :nil_or_empty? :empty? unless respond_to? :nil_or_empty?
end

class Hash
  alias :nil_or_empty? :empty? unless respond_to? :nil_or_empty?
end
