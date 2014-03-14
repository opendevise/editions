module Editions

EditionNumberRx = /^\d+\.\d+$/

class EditionNumber
  class << self
    def parse string
      string.split '.'
    end
  end
end

class Edition
  attr_reader :vol_num
  attr_reader :issue_num
  attr_accessor :pub_date
  attr_accessor :periodical
  attr_reader :month
  attr_reader :month_formatted

  def initialize vol_num, issue_num, pub_date, periodical = nil
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
    @month = pub_date.strftime '%Y-%m'
    @month_formatted = pub_date.strftime '%B %Y'
    @periodical = periodical
  end

  def number
    %(#{@vol_num}.#{@issue_num})
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
