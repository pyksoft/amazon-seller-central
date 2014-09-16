AWS_ACCESS_KEY_ID ='AKIAJWUX7FTA4K5RSLRQ'
AWS_SECRET_ACCESS_KEY = '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'

Amazon::Ecs.options = {
    :associate_tag => 'tag',
    :AWS_access_key_id => AWS_ACCESS_KEY_ID,
    :AWS_secret_key => AWS_SECRET_ACCESS_KEY
}



class Hash
  def diff(other)
    (self.keys + other.keys).uniq.inject({}) do |memo, key|
      unless self[key] == other[key]
        if self[key].kind_of?(Hash) &&  other[key].kind_of?(Hash)
          memo[key] = self[key].diff(other[key])
        else
          memo[key] = [self[key], other[key]]
        end
      end
      memo
    end
  end
end

class ActiveRecord::Base
  def serializable_attributes
    HashWithIndifferentAccess.new attributes
  end
end

class String
  def string_between_markers(marker1, marker2)
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end
end