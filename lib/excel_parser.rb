class ExcelParser
  def self.cols_to_hash(filename,cols=[],opts={})
    Roo::Spreadsheet.open(filename,opts.slice(:extension)).each_with_index.map do |r,i|
      #ignoring first row
      next if i == 0 || !r

      r.map!{|v| v.is_a?(Float) && v.denominator == 1 ? v.to_i : v} # fixed integer float(13.0)

      Hash[cols.zip(r)]
    end.slice(1..-1)
  end
end