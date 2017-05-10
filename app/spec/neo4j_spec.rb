require 'spec_helper'
require_relative '../neo4j_api'

describe "neo4j-API integration" do

	before(:each) do
		# Use the neo4j-test docker container, run rspec from localhost
		test_config = {"port" => 7475, "server" => "localhost"}
		@neo = Neo4j.new(test_config)
		@neo.clean
	end

	it 'Neo4j Test DB has zero nodes' do
		expect(@neo.count_nodes).to equal(0)
	end

	it 'Pinyin chart is imported correctly' do
		path = File.join(File.dirname(__FILE__), 'data/pinyinchart.csv')
		@neo.add_pinyin_blocks(path)
		expect(@neo.count_nodes).to equal(53)
		b = @neo.find_pinyin_block("eng")
		expect(b).to eq({block: "eng", cons: "No-Cons", vow: "eng"})
		b = @neo.find_pinyin_block("huang")
		expect(b).to eq({block: "huang", cons: "h", vow: "uang"})
	end

end
