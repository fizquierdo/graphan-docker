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

	describe "Import of word lists" do 
		before(:each) do
			url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/spec/data/hsk_words.tsv"
			@neo.import_words(url)
		end

		it 'imports all expected words' do
			expect(@neo.count_nodes).to equal(11)
		end

		it 'creating multiple nodes for characters with multiple meanings' do
			cypher = "MATCH (n:Word{simp:'累'})
								RETURN n.simp as simp, n.pinyin as pinyin, n.eng as eng"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(3)
			ret_lei_tired = ret.select{|r| r[:pinyin] == "lei4"}.first
			expect(ret_lei_tired[:pinyin]).to eq("lei4")
			expect(ret_lei_tired[:eng]).to eq("tired")
		end

		it 'splitting tones correctly' do
			cypher = "MATCH (w:Word{simp:'正在'})
								RETURN w.pinyin as pinyin, w.pinyin_tones as tones, w.pinyin_blocks as blocks"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:blocks]).to match_array(%w(zheng zai))
			expect(ret.first[:tones]).to match_array(%w(4 4))
		end

		it 'word node has all expected properties' do
			word_properties = %w(hsk unique eng trad simp pinyin pinyin_tonemarks pinyin_blocks pinyin_tones)
			cypher = "MATCH (n:Word{simp:'鱼'})
								RETURN keys(n) as properties"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:properties]).to match_array(word_properties)
		end

	end

end
