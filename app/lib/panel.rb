require 'terminal-table'

class Panel
	attr_reader :levels, :states, :values

	def initialize(query_counts)
		# query_counts <- [{rel: IGNORES|LEARNING|KNOWS, level: HSK_STR, count: INT},{}]
		@levels = 1.upto(6).to_a.map{|l| l.to_s}
		@states = %w(IGNORES LEARNING KNOWS)

	  # @values[level][state] = count
		# initialization to 0 counts
		@values = Hash[@levels.map{|l| [l, Hash[@states.map{|s| [s,0]}]]}] 

		query_counts.each do |h|
			count = h[:count]
			state = h[:rel]
			level = h[:level]
			@values[level][state] = count 
		end
	end

	def counts_table 
		rows = []
		@states.each do |state|
			row = [state]
			tot = 0 
			@levels.each do |level|
				row << @values[level][state]
				tot += @values[level][state]
			end
			row << tot
			rows << row
		end

		# add a final total row
		sum_row = ['Total'] + [0] * (@levels.size + 1)
		rows.each_with_index do |row, row_i|
			row.each_with_index do |value, i|
				sum_row[i]+= value if i > 0
			end
		end
		rows << sum_row

		headings = [:state] + @levels + [:All]
		[headings, rows]
	end

	def backbone_table(disconn, connect, words_connected)
		# Format results of character_connected queries into table rows
		headings = ['chars-in-bb', 'chars-not-repr', 'words-via-bb', 'level']
		l = @levels
		[disconn, connect, words_connected].each do |counter|
			raise "Unexpected size #{counter.size}" if counter.size != l.size 
		end
		rows = l.each_with_index.map do |level, i|
			  [connect[i][:count], disconn[i][:count], words_connected[i][:count], level]
		end
		[headings, rows]
	end

end
