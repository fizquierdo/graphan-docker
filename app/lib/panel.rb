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
		rows.each_with_index do |row|
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
		rows = @levels.map do |level|
				row = []
				[connect, disconn, words_connected].each do |a|
					counter = a.select{|c| c[:level] == level}
					if counter.empty?
						count = 0
					else
						raise "Unexpected size #{counter.size}" unless counter.size == 1
						count = counter.first[:count] 
					end
					row << count
				end
				row << level
				row
		end
		[headings, rows]
	end
	def backbone_table_inverted(table)
		headings, rows = table
		all_rows = [headings] + rows 		
		new_table = all_rows.transpose
		new_headings = new_table.pop
		[new_headings, new_table]
	end

end
