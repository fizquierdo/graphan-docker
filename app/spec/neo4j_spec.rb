require 'spec_helper'
require_relative '../neo4j_api'

def init_test_db
	# Use the neo4j-test docker container, run rspec from localhost
	test_config = {"port" => 7475, "server" => "localhost"}
	@neo = Neo4j.new(test_config)
	@neo.clean
end

def import_pinyin_blocks
		path = File.join(File.dirname(__FILE__), 'data/pinyinchart.csv')
		@neo.add_pinyin_blocks(path)
end
def import_radicals
		path = File.join(File.dirname(__FILE__), 'data/radical_list.csv')
		@neo.add_radicals(path)
end
def import_words
		url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/spec/data/hsk_words.tsv"
		@neo.import_words(url)
end
def import_backbone
		backbone_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/spec/data/backbone.csv"
		@neo.add_backbone(backbone_url)
end
def add_freq_ranks_to_characters
		char_ranks_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/spec/data/character_frequency.tsv"
		@neo.add_freq_rank_to_characters(char_ranks_url)
end


describe "Neo4j-API integration" do

	before(:each) do
		init_test_db
	end

	it 'Neo4j Test DB has zero nodes' do
		expect(@neo.count_nodes).to equal(0)
	end

end

describe "Queries for tone list" do
	before(:each) do
		init_test_db
		import_words
		@neo.create_tone_combos_from_words
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
		@neo.create_user(@user_data)
	end
	describe "words grouped by tones" do
		it "returns edited triplets with num, words_by_state, tone" do
			# tone 44 and 4 single tones
			ret = @neo.words_grouped_by_tones('Bob')
			expect(ret.size).to eq(5)
			# all arrays have 3 elements
			expect(ret.map{|l| l.size}.uniq.first).to eq(3)
		end
		it "groups words by state" do
			# tone 44 and 4 single tones
			ret = @neo.words_grouped_by_tones('Bob')
			tone_44 = ret.select{|a| a[2] == "44"}.first
			expect(tone_44[1].has_key? ("IGNORES")).to be true
			expect(tone_44[1]["IGNORES"].first).to eq("正在")
		end
	end
end

describe "Queries for backbone" do
	before(:each) do
		init_test_db
		import_words
		@neo.create_characters_from_words
		add_freq_ranks_to_characters
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
		@neo.create_user(@user_data)
		import_backbone
	end

	describe "backbone" do
		it "returns complete backbone" do
			ret = @neo.backbone('Bob')
			expect(ret.size).to eq(12)
		end
		it "returns backbone entries ordered by ID" do
			ret = @neo.backbone('Bob')
			expect(ret.first[:simp]).to eq('一')
			expect(ret.first[:backbone_id]).to eq('1')
			expect(ret.last[:simp]).to eq('人')
			expect(ret.last[:backbone_id]).to eq('12')
		end
		it "relationship with word if available" do
			ret = @neo.backbone('Bob')
			yi_node = ret.select{|b| b[:simp] == '一'}.first
			expect(yi_node[:words_rel].first).to eq("IGNORES")
		end
	end

	describe "backbone node" do
		it "returns single backbone node" do
			ret = @neo.backbone_node('Bob', '1')
			expect(ret[:backbone_id]).to eq('1')
			expect(ret[:simp]).to eq('一')
		end
		it "returns related word status" do
			ret = @neo.backbone_node('Bob', '1')
			expect(ret[:words].size).to eq(1)
			w = ret[:words].first
			expect(w[:word_rel]).to eq('IGNORES')
			expect(w[:level]).to eq('1')
			expect(w[:word_simp]).to eq('一')
			expect(w[:word_unique]).to eq('一(yi1)')
		end
		# TODO add tests for parts, freq_rank, composites
	end
end

describe "Queries for Words view" do
	before(:each) do
		init_test_db
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
	end

	describe "words" do
		before(:each) do
			import_words
			@neo.create_user(@user_data)
		end

		it 'returns all words' do
			ret = @neo.words('Bob')
			expect(ret.size).to eq(12)
		end
		it 'returns all words as IGNORES' do
			ret = @neo.words('Bob')
			expect(ret.map{|w| w[:rel]}.uniq.first).to eq('IGNORES')
		end
	end
end

describe "Queries for index view" do

	before(:each) do
		init_test_db
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
	end

	describe "words_top" do

		before(:each) do
			import_words
			import_radicals
			@neo.create_characters_from_words
			@neo.create_pinyin_from_words
			import_backbone
			@neo.create_user(@user_data)
		end

		it 'returns 1 words as ignore for just created user for top 1' do
			ret = @neo.words_top('Bob', 'IGNORES', 1)
			expect(ret.size).to eq(1)
			w = ret.first
			expect(w[:simp]).to eq("一")
			expect(w[:backbone_id]).to eq("1")
			expect(w[:level]).to eq("1")
			expect(w[:word_rel]).to eq("IGNORES")
		end

		it 'returns 1 words as ignore for just created user for top 5' do
			ret = @neo.words_top('Bob', 'IGNORES', 5)
			expect(ret.size).to eq(1)
		end

		it 'returns 0 words as LEARNING for just created user for top 5' do
			%w(LEARNING KNOWS).each do |state|
				ret = @neo.words_top('Bob', state, 1)
				expect(ret.size).to eq(0)
				expect(ret.empty?).to be true
			end
		end

		it 'returns empty array for unlogged-user' do
			ret = @neo.words_top('unlogged-user', 'IGNORES', 1)
			expect(ret.empty?).to be true
		end
		# TODO test the ORDER BY aspect of the query
	end

	describe "words_last_timestamp" do
		before(:each) do
			@neo.run_cypher("CREATE (w:Word{simp:'课'})")
			@neo.create_user(@user_data)
		end
		it 'returns 1 simplified character and a recent date' do
			simp, date = @neo.words_last_timestamp('Bob', 'IGNORES')
			expect(simp).to eq('课')
			expect(date).to eq(Time.now.strftime("%Y-%m-%d"))
		end
		it 'returns no simplified character and oldest date' do
			%w(LEARNING KNOWS).each do |state|
				simp, date = @neo.words_last_timestamp('Bob', state)
				expect(simp).to be nil
				expect(date).to eq("1970-01-01")
			end
		end
	end

	describe "word_user_counts" do
		before(:each) do
			@neo.run_cypher("CREATE (w:Word{simp:'课', hsk: 1, unique: 'uid'})")
			@neo.create_user(@user_data)
		end
		it 'returns empty array for unlogged-user' do
			ret = @neo.word_user_counts('unlogged-user')
			expect(ret.empty?).to be true
		end
		it 'returns 1 word and it is ignored' do
			ret = @neo.word_user_counts('Bob')
			expect(ret.size).to eq(1)
			expect(ret.first[:level]).to eq(1)
			expect(ret.first[:rel]).to eq('IGNORES')
		end
		it 'returns multiple words and one is LEARNING' do
			%w(一 二 三).each do |w|
				@neo.run_cypher("CREATE (w:Word{simp:'#{w}', hsk: 2, unique: 'uid'})")
				cypher = "MATCH (bob:Person{name: 'Bob'}), (w:Word{simp: '#{w}'})
									CREATE (bob)-[:LEARNING]->(w)"
				@neo.run_cypher(cypher)
			end
			ret = @neo.word_user_counts('Bob')
			expect(ret.size).to eq(2)
			learning = ret.select{|c| c[:rel] == "LEARNING"}
			expect(learning.size).to eq(1)
			expect(learning.first[:count]).to eq(3)
			expect(learning.first[:level]).to eq(2)
		end
	end

	describe "word_bb_counts and characters_connected" do
		before(:each) do
			cypher = "
			CREATE (:Word{simp:'课', hsk: '1', unique: 'uid'})
			CREATE (:Word{simp:'课', hsk: '1', unique: 'uid_alt'})
			CREATE (:Word{simp:'一', hsk: '1', unique: 'uid_1'})
			CREATE (:Word{simp:'二', hsk: '1', unique: 'uid_1'})
			CREATE (:Character{simp:'课'})
			CREATE (:Backbone{simp:'课'})
			"
			@neo.run_cypher(cypher)
			cypher = "
			MATCH (ch:Character{simp: '课'}), (w:Word{simp: '课'}), (b:Backbone{simp: '课'})
			CREATE (w)-[:HAS_CHARACTER]->(ch)
			CREATE (b)-[:IS_CHARACTER]->(ch)
			CREATE (b)-[:IS_WORD]->(w)
			"
			@neo.run_cypher(cypher)
		end
		it "counts words per hsk level accessible via backbone" do 
			ret = @neo.word_bb_counts
			expect(ret.size).to eq(1)
			expect(ret.first[:count]).to eq(2)
			expect(ret.first[:level]).to eq('1')
		end
		it "counts characters connected via backbone" do 
			ret = @neo.characters_connected(true)
			expect(ret.size).to eq(1)
			expect(ret.first[:count]).to eq(1)
		end
		it "counts characters not connected via backbone" do 
			ret = @neo.characters_connected(false)
			expect(ret.size).to eq(1)
			expect(ret.first[:count]).to eq(2)
		end
		it "accounts for different hsk levels" do 
			cypher = "CREATE (:Word{simp:'三', hsk: '2', unique: 'uid_2'})"
			@neo.run_cypher(cypher)
			ret = @neo.characters_connected(false)
			expect(ret.size).to eq(2)
		end
	end

end

describe "Neo4j exports/imports" do
	before(:each) do
		init_test_db
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
	end
	describe "Data can be imported from file" do
		before(:each) do
			path = File.join(File.dirname(__FILE__), 'data/user_db.csv')
			@neo.import_users(path)
		end

		it 'Users can be imported' do
			users = @neo.get_users('Alice')
			expect(users.size).to equal(1)
			user = users.first
			expect(user[:name]).to eq('Alice')
			expect(user[:hash]).to eq('$hashtest')
		end

		it 'Users rels can be imported' do
			@neo.run_cypher("CREATE (w:Word{unique:'几(ji3)', simp: '几'})")
			path = File.join(File.dirname(__FILE__), 'data/user_db_rels.csv')
			@neo.import_users_rels(path)
			simp, date = @neo.words_last_timestamp('Alice', 'IGNORES')
			expect(simp).to eq('几')
			expect(date).to eq('2017-01-28')
		end

	end

	describe "Data can be exported to file" do
		before(:each) do
			@fname = "exported_file.csv"
		end

		it 'File can be exported' do
			@neo.export_users(@fname)
			lines = File.open(@fname).readlines
			expect(lines.size).to eq(1)
			k1, k2 = lines.first.chomp.split(',')
			expect(k1).to eq('name')
			expect(k2).to eq('hash')
		end

		it 'User file can be exported' do
			@neo.create_user(@user_data)
			@neo.export_users(@fname)
			lines = File.open(@fname).readlines
			expect(lines.size).to eq(2)
			name, hash = lines.last.chomp.split(',')
			expect(name).to eq('Bob')
			expect(hash).to eq('hashedvalue')
		end

		it 'User without relationships can be exported' do
			@neo.export_users_rels(@fname)
			lines = File.open(@fname).readlines
			expect(lines.size).to eq(1)
			k1, k2, k3, k4 = lines.last.chomp.split(',')
			expect(k1).to eq('person_name')
			expect(k2).to eq('rel')
			expect(k3).to eq('timestamp')
			expect(k4).to eq('word_unique')
		end

		it 'User with relationships can be exported' do
			@neo.run_cypher("CREATE (w:Word{simp:'hey', unique: 'heya'})")
			@neo.create_user(@user_data)
			@neo.export_users_rels(@fname)
			lines = File.open(@fname).readlines
			expect(lines.size).to eq(2)
			person_name, rel, timestamp, word_unique = lines.last.chomp.split(',')
			date = Time.at((timestamp.to_f / 1000).to_i).strftime("%Y-%m-%d")

			expect(person_name).to eq('Bob')
			expect(rel).to eq('IGNORES')
			expect(date).to eq(Time.now.strftime("%Y-%m-%d"))
			expect(word_unique).to eq('heya')
		end

		after(:each) do
			File.delete(@fname)
		end
	end

end

describe "Neo4j User management" do

	before(:each) do
		init_test_db
		@user_data = {name: 'Bob', hash: 'hashedvalue'}
	end

	describe "User creation" do

		it 'User can be created' do
			@neo.create_user(@user_data)
			expect(@neo.count_nodes).to equal(1)
		end

		it 'User details can be retrieved' do
			@neo.create_user(@user_data)
			users = @neo.get_users('Bob')
			expect(users.size).to equal(1)
			user = users.first
			expect(user[:name]).to eq('Bob')
			expect(user[:hash]).to eq('hashedvalue')
		end

		it 'Two different users can be created' do
			@neo.create_user(@user_data)
			@neo.create_user({name: 'Alice', hash: 'hashedvalue'})
			expect(@neo.count_nodes).to equal(2)
		end

		it 'User starts ignoring all words in DB' do
			words = %w(一 在)
			words.each {|w| @neo.run_cypher("CREATE (w:Word{simp:'#{w}'})")}
			@neo.create_user(@user_data)

			cypher = "MATCH (user:Person{name: 'Bob'})-[:IGNORES]->(w:Word)
								RETURN w.simp as simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to equal(words.size)
			expect(ret.map{|b| b[:simp]}).to match_array(words)
		end

	end

end

describe "Neo4j DB seeds" do 

	before(:each) do
		init_test_db
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
			import_radicals
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
			import_words
		end

		it 'imports all expected words' do
			expect(@neo.count_nodes).to equal(12)
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
			expect(ret.first[:cnt]).to eq(12)
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
			expect(ret.first[:cnt]).to eq(5)
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
			expect(ret.first[:cnt]).to eq(10)
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
			@neo.create_characters_from_words
			add_freq_ranks_to_characters
			cypher = "
			MATCH (ch:Character) 
			RETURN ch.simp as simp, ch.freq_rank as rank"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(10)
			expect(ret.select{|ch| ch[:simp] == "这"}.first[:rank]).to eq(11)
			expect(ret.select{|ch| ch[:simp] == "在"}.first[:rank]).to be_nil
		end

		it 'characters can be linked to radicals' do
			import_radicals
			char_radicals_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/data/hsk_radicals.csv"
			@neo.create_characters_from_words
			@neo.link_characters_to_radicals(char_radicals_url)
			cypher = "
			MATCH (ch:Character)-[:HAS_RADICAL]->(rd:Radical)
			RETURN ch.simp as char, rd.simp as rad"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(3)
			expect(ret.select{|ch| ch[:char] == "一"}.first[:rad]).to eq("一")
			expect(ret.select{|ch| ch[:char] == "在"}.first[:rad]).to eq("亻")
			expect(ret.select{|ch| ch[:char] == "正"}.first[:rad]).to eq("一")
		end

	end

	describe "Import of backbone" do 
		before(:each) do
			import_radicals
			import_words
			@neo.create_characters_from_words
			import_backbone
		end

		it 'imports backbone nodes' do
			cypher = "MATCH (b:Backbone) RETURN count(b) as cnt"
			ret = @neo.run_cypher(cypher)
			expect(ret.first[:cnt]).to eq(15)
		end
		it 'backbone has backbone parts' do
			cypher = "MATCH (b:Backbone{backbone_id: '10'})<-[:PART_OF]-(part:Backbone) 
								RETURN part.backbone_id as b_id"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(2)
			expect(ret.map{|b|b[:b_id]}).to match_array(%w(7 10a))
		end
		it 'backbone nodes are a linked list' do
			cypher = "MATCH (b:Backbone)-[:NEXT]->(next:Backbone) 
								RETURN next.backbone_id as b_id"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(12)
		end
		it 'backbone connected to radicals' do
			cypher = "MATCH (b:Backbone)-[:IS_RADICAL]->(rad:Radical) 
								RETURN b.backbone_id as b_id, rad.simp as simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(4)
			expect(ret.select{|b|b[:b_id] == "1"}.first[:simp]).to eq("一")
		end
		it 'backbone connected to words' do
			cypher = "MATCH (b:Backbone)-[:IS_WORD]->(w:Word) 
								RETURN b.backbone_id as b_id, w.simp as simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:simp]).to eq("一")
		end
		it 'backbone connected to characters' do
			cypher = "MATCH (b:Backbone)-[:IS_CHARACTER]->(ch:Character) 
								RETURN b.backbone_id as b_id, ch.simp as simp"
			ret = @neo.run_cypher(cypher)
			expect(ret.size).to eq(1)
			expect(ret.first[:simp]).to eq("一")
		end
	end

end
