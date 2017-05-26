ENV['RACK_ENV'] = nil  

require 'spec_helper'
require 'rack/test'
require_relative '../lib/panel'

describe "Panel helpers" do

	before(:each) do
		user_counts = [{rel: "IGNORES", level: 1, count: 1}]
		@panel = Panel.new user_counts
		@states = %w(IGNORES LEARNING KNOWS)
		@levels = 1.upto(6).to_a
	end

	describe "Panel initialization" do

		it 'panel has the expected counts' do
			expect(@panel.values.keys).to match_array(@levels)
			@panel.values.each_pair do |level, level_states|
				expect(level_states.keys).to match_array(@states)
				level_states.each_pair do |state, count|
					if state == "IGNORES" and level == 1
						expect(count).to eq(1)
					else
						expect(count).to eq(0)
					end
				end
			end
		end

	end

	describe "Counts table" do
		it 'returns correct headers' do
			headings, _ = @panel.counts_table
			expect(headings).to match_array([:state, 1, 2, 3, 4, 5, 6, :All])
		end
		it 'returns correct rows' do
			_ , rows = @panel.counts_table
			expect(rows.size).to eq(4)
			ignored_row = rows.select{|r| r[0] == "IGNORES"}.first
			expect(ignored_row[1]).to eq(1) # count for level 1 is 1 for IGNORED state
			expect(ignored_row[2]).to eq(0) # count for level 2 is 0 for IGNORED state
			expect(ignored_row[7]).to eq(1) # count for level :All is 1 for IGNORED state
			state_values = rows.map{|r| r[0]}
			expect(state_values).to match_array(%w(IGNORES LEARNING KNOWS Total))
		end
	end


end
