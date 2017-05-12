require 'spec_helper'
require_relative '../neo4j_api'


def init_test_db
	# Use the neo4j-test docker container, run rspec from localhost
	test_config = {"port" => 7475, "server" => "localhost"}
	@neo = Neo4j.new(test_config)
	@neo.clean
end

describe "neo4j-API integration" do

	before(:each) do
		init_test_db
	end

	it 'Neo4j Test DB has zero nodes' do
		expect(@neo.count_nodes).to equal(0)
	end

end

describe "DB seeds" do 

	before(:each) do
		init_test_db
	end

	describe "Import of pinyin blocks" do 
		it 'imports blocks with cons prefix and vowel suffix' do
			path = File.join(File.dirname(__FILE__), 'data/pinyinchart.csv')
			@neo.add_pinyin_blocks(path)
			expect(@neo.count_nodes).to equal(53)
			b = @neo.find_pinyin_block("eng")
			expect(b).to eq({block: "eng", cons: "NA", vow: "eng"})
			b = @neo.find_pinyin_block("huang")
			expect(b).to eq({block: "huang", cons: "h", vow: "uang"})
		end
	end

	describe "Import of radical lists" do 
		before(:each) do
			path = File.join(File.dirname(__FILE__), 'data/radical_list.csv')
			@neo.add_radicals(path)
		end

		it 'imports all expected radicals' do
			expect(@neo.count_nodes).to equal(18)
			%w(一 乚 八 丷).each do |simp|
				r = @neo.find_radical(simp)
				expect(r).to eq({simp: simp})
			end
		end

		it 'creates a VARIANT_OF relationship' do
			cypher = "MATCH (n:Radical{simp:'丷'})-[:VARIANT_OF]->(variant)
								RETURN n.simp as simp, variant.simp as variant_simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:variant_simp]).to eq('八')
		end

	end
end
