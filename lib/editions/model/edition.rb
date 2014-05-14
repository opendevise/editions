require 'forwardable'

module Editions

EditionNumberRx = /^\d+\.\d+$/
EditionDateRx = /^\d{4}-\d{2}$/

class EditionNumber
  class << self
    def parse string
      string.split '.', 2
    end
  end
end

class Edition
  extend Forwardable
  attr_reader :vol_num
  attr_reader :issue_num
  attr_accessor :title
  attr_accessor :pub_date
  attr_accessor :publication
  attr_reader :month
  attr_reader :month_formatted
  def_delegator :@publication, :publisher
  #def_delegator :@publication, :name, :publication_name

  def initialize vol_num, issue_num, pub_date, publication = nil, title = nil
    if vol_num.is_a? Array
      @vol_num = %(#{vol_num[0]})
      @issue_num = %(#{vol_num[1]})
    elsif (vol_num = %(#{vol_num})).include? '.'
      @vol_num, @issue_num = EditionNumber.parse vol_num
    else
      @vol_num = vol_num
      @issue_num = %(#{issue_num})
    end

    if (pub_date.is_a? String)
      pub_date = DateTime.parse(pub_date.count('-') >= 2 ? pub_date : %(#{pub_date}-01))
    end

    @pub_date = pub_date
    @month = pub_date.strftime '%Y-%m' if pub_date
    @month_formatted = pub_date.strftime '%B %Y' if pub_date
    @publication = publication
    @title = title
  end

  def number
    %(#{@vol_num}.#{@issue_num})
  end

  def handle
    raise ArgumentError, 'Cannot determine handle for edition, publication not defined' unless @publication
    #[@publication.handle, year_month].compact * '-'
    [@publication.handle, number].compact * '-v'
  end

  def full_title
    raise ArgumentError, 'Cannot determine full_title for edition, publication not defined' unless @publication
    @title ? %(#{@publication.name} - #{month_formatted}: #{@title}) : %(#{@publication.name} - #{month_formatted})
  end

  def description
    raise ArgumentError, 'Cannot determine description for edition, publication not defined' unless @publication
    edition_formatted = '%s Edition of %s' % [month_formatted, @publication.name]
    @publication.description ? %(#{edition_formatted}: #{@publication.description.tr_s "\n", ' '}) : edition_formatted
  end

  alias :volume :vol_num
  alias :volume_num :vol_num
  alias :volume_number :vol_num

  alias :issue :issue_num
  alias :issue_num :issue_num

  alias :date :pub_date
  alias :publication_date :pub_date

  alias :year_month :month
end
end
