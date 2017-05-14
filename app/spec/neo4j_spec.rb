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

	def import_pinyin_blocks
			path = File.join(File.dirname(__FILE__), 'data/pinyinchart.csv')
			@neo.add_pinyin_blocks(path)
	end

	describe "Import of pinyin blocks" do 
		it 'imports blocks with cons prefix and vowel suffix' do
			import_pinyin_blocks
			expect(@neo.count_nodes).to equal(90)
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

		it 'words are linked to pinyin blocks' do
			import_pinyin_blocks
			@neo.link_words_with_pinyin_blocks
			cypher = "MATCH (w:Word{simp:'正在'})-[:HAS_PINYIN_BLOCK]->(block:PinyinBlock)
								RETURN block.block as block"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(2)
			expect(ret.map{|b| b[:block]}).to match_array(%w(zheng zai))
		end

		it 'pinyin words can be extracted from words' do
			@neo.create_pinyin_from_words
			cypher = "MATCH (pw:PinyinWord)
								RETURN count(pw) as cnt"
			ret = @neo.run_cypher(cypher)
			expect(ret.first[:cnt]).to eq(11)
		end
		it 'words can be linked to pinyin word nodes' do
			@neo.create_pinyin_from_words
			cypher = "MATCH (w:Word{simp:'正在'})-[:HAS_PINYIN]->(pw:PinyinWord)
								RETURN pw.pinyin as pinyin"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:pinyin]).to eq("zheng4zai4")
		end

		it 'pinyin tone combos can be extracted from words' do
			@neo.create_tone_combos_from_words
			cypher = "MATCH (tn:ToneCombo) RETURN count(tn) as cnt"
			ret = @neo.run_cypher(cypher)
			expect(ret.first[:cnt]).to eq(4)
		end
		it 'words can be linked to pinyin word nodes' do
			@neo.create_tone_combos_from_words
			cypher = "
			MATCH (w:Word{simp:'正在'})-[:HAS_TONE]->(tn:ToneCombo)
			RETURN tn.tone as tone_combo"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:tone_combo]).to eq("44")
		end

		it 'Characters can be extracted from words' do
			@neo.create_characters_from_words
			cypher = "MATCH (ch:Character) RETURN count(ch) as cnt"
			ret = @neo.run_cypher(cypher)
			expect(ret.first[:cnt]).to eq(9)
		end
		it 'words are linked characters' do
			@neo.create_characters_from_words
			cypher = "MATCH (w:Word{simp:'正在'})-[:HAS_CHARACTER]->(ch:Character)
								RETURN ch.simp as simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(2)
			expect(ret.map{|b| b[:simp]}).to match_array(%w(正 在))
		end
		it 'freq ranks can be added to characters' do
			char_ranks_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/spec/data/character_frequency.tsv"
			@neo.create_characters_from_words
			@neo.add_freq_rank_to_characters(char_ranks_url)
			cypher = "
			MATCH (ch:Character) 
			RETURN ch.simp as simp, ch.freq_rank as rank"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(9)
			expect(ret.select{|ch| ch[:simp] == "这"}.first[:rank]).to eq(11)
			expect(ret.select{|ch| ch[:simp] == "在"}.first[:rank]).to be_nil
		end

		it 'characters can be linked to radicals' do
			path = File.join(File.dirname(__FILE__), 'data/radical_list.csv')
			@neo.add_radicals(path)
			char_radicals_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/data/hsk_radicals.csv"
			@neo.create_characters_from_words
			@neo.link_characters_to_radicals(char_radicals_url)
			cypher = "
			MATCH (ch:Character)-[:HAS_RADICAL]->(rd:Radical)
			RETURN ch.simp as char, rd.simp as rad"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(2)
			expect(ret.select{|ch| ch[:char] == "在"}.first[:rad]).to eq("亻")
			expect(ret.select{|ch| ch[:char] == "正"}.first[:rad]).to eq("一")
		end

	end

end
