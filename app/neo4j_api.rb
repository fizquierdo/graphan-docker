require 'neography'
require "csv"

class String
	def numeric?
		Float(self) != nil rescue false
	end
end

# Example API used by the sinatra app to interact with Neo4j
# All Cypher queries should be here
# See spec/neo4j_spec

class Neo4j
	def initialize(config)
		if config["username"].nil?
			# DEV and TEST env do not use authentication
			@neo = Neography::Rest.new({port: config["port"], 
                                  server: config["server"]})
		else
			# username/password defaults to "neo4j", updated after creating DB
			@neo = Neography::Rest.new({port: config["port"],
                                  server: config["server"],
                                  username: config["username"],
                                  password: config["password"]})
		end
	end

	#### 
	# Texts 
	#
	def create_text(text)
		# Add a user node to the db where 
		# text <- {title: str, source: str, text: str}
		node = @neo.create_node(text)
		@neo.add_label(node, "Text")
	end
	def get_texts
		cypher = "
		MATCH (t:Text) 
		RETURN t.title as title, t.source as source, t.text as text"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end


	#### 
	# Users 
	#
	def get_users(username)
		cypher = "
		MATCH (p:Person{name:'#{username}'}) 
		RETURN p.name as name, p.hash as hash"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end

	def create_user(user)
		# Add a user node to the db where 
		# user <- {name: params[:username], hash: hash}
		node = @neo.create_node(user)
		@neo.add_label(node, "Person")
		initialize_user(user[:name])
	end

	def initialize_user(name)
		# the person should start ignoring all words
		cypher = "
		MATCH (p:Person {name:'#{name}'}), (w:Word)
		CREATE (p)-[:IGNORES{date: TIMESTAMP()}]->(w)"
		@neo.execute_query(cypher)
	end
	
	#### 
	# Export 
	#

	def export_users(filename)
		cypher = "MATCH (p:Person) RETURN p.name as name, p.hash as hash"
		export(filename, cypher)
	end

	def export_users_rels(filename)
		cypher = "MATCH (p:Person)-[r]->(w:Word) 
		         RETURN p.name as person_name,
		                type(r) as rel, 
		                r.date as timestamp, 
		                w.unique as word_unique"
		export(filename, cypher)
	end

	#### 
	# Import 
	#
	
	def import_users(filename)
		users = CSV.read(filename, headers: true, skip_blanks: true)
		users.each do |u|
			node = @neo.create_node(name: u["name"], hash: u["hash"])
			@neo.add_label(node, "Person")
		end
	end
	def import_users_rels(filename)
		users_rels = CSV.read(filename, headers: true, skip_blanks: true)
		users_rels.each do |row|
			 query =  "
				MATCH (p:Person{name: '#{row['person_name']}'}), 
							(w:Word{unique: '#{row['word_unique']}' })
				CREATE UNIQUE (p)-[:#{row['rel']}{date: #{row['timestamp']}}]->(w)"
			 @neo.execute_query(query)
		end
	end

	def add_pinyin_blocks(filename)
		# Add all possible pinyin sounds from a table file in csv format
		pinyin = CSV.read(filename, headers: true)
		py_chart_blocks = {}

		vowels = pinyin.headers - ["cons"]
		pinyin.each do |p|
			cons = p["cons"] 
			vowels.each do |vow|
				unless p[vow].nil?
					chart_block = p[vow]
					py_chart_blocks[chart_block] = {cons: cons, vow: vow, words: []}
					cypher = "MERGE (b:PinyinBlock {cons:'#{cons}',vow:'#{vow}',block:'#{chart_block}'}) RETURN b"
					@neo.execute_query(cypher)
				end
			end
		end
		py_chart_blocks
	end

	def add_radicals(radical_filename)
		# add radical nodes from radical filelist, variants separated by ;
		radicals =  CSV.read(radical_filename, headers: true, skip_blanks: true)
		radicals.each do |radical|
			h = Hash[radicals.headers.map{|item| [item.to_sym, radical[item]] }]
			# 160 is an HTML &nbsp non-breaking space 
			h[:simp] = h[:trad] if h[:simp].ord == 160
			if h[:variants].ord == 160
				h[:variants] = "NA"
				node = @neo.create_node h
				@neo.add_label(node, "Radical")
			else
				h[:variants] = h[:variants].split(';')
				node = @neo.create_node h
				@neo.add_label(node, "Radical")
				# add nodes for the variants too
				h[:variants].each do |variant|
					if variant.include? '('
						variant_simp, note = variant.split('(')
						note = note.delete(')').strip
					else
						variant_simp = variant
						note = "NA"
					end
					variant_h = {:simp => variant_simp.strip, :note => note}
					variant_node = @neo.create_node variant_h
					@neo.add_label(variant_node, "Radical")
					@neo.create_relationship("VARIANT_OF", variant_node, node)
				end
			end
		end
	end

	def import_words(words_url)
		cypher = "
		LOAD CSV WITH HEADERS FROM '#{words_url}' as line
		FIELDTERMINATOR '\t' 
		CREATE (:Word {simp: line.simp, 
		unique:line.simp + '('+line.pinyin+')', 
		trad:line.trad, 
		hsk: line.hsk, 
		pinyin: line.pinyin, 
		pinyin_tonemarks: line.pinyin_tonemarks, 
		pinyin_blocks: split(line.pinyin_blocks,','), 
		pinyin_tones: split(line.pinyin_tones,','), 
		eng: line.eng})"
		@neo.execute_query(cypher)
	end
	def link_words_with_pinyin_blocks
		cypher = "
		MATCH (w:Word)
		WITH w.pinyin_blocks as blocks, w
		UNWIND blocks as block
		MATCH (available_block:PinyinBlock{block: block})
		CREATE UNIQUE (w)-[:HAS_PINYIN_BLOCK]->(available_block)"
		@neo.execute_query(cypher)
	end

	# Pinyin words
	def create_pinyin_from_words
		cypher = "
		MATCH (w:Word) 
		WITH DISTINCT w.pinyin as pw, w.pinyin_tonemarks as tm, w as word
		MERGE (py:PinyinWord{pinyin: pw, pinyin_tm: tm})
		CREATE UNIQUE (word)-[:HAS_PINYIN]->(py)"
		@neo.execute_query(cypher)
	end

	# Pinyin Combos
	def create_tone_combos_from_words
		# Create tone combos, e.g. zheng4zai4 has tones [4,4] and combo 44
		cypher = "
		MATCH (w:Word) 
		WITH DISTINCT w.pinyin_tones as tones, w as word
		MERGE (tn:ToneCombo {tone: reduce(acc = '', x IN tones | acc + x)})
		CREATE UNIQUE (word)-[:HAS_TONE]->(tn)"
		@neo.execute_query(cypher)
	end

	# Characters
	def create_characters_from_words
		cypher = "
		MATCH (w:Word) 
		WITH split(w.simp,'') as simplified_characters, w as word
		UNWIND simplified_characters as simplified_char
		MERGE (ch:Character {simp: simplified_char})
		CREATE UNIQUE (word)-[:HAS_CHARACTER]->(ch)"
		@neo.execute_query(cypher)
	end
	def add_freq_rank_to_characters(char_ranks_url)
		# Create a property freq_rank if the character is present in the tsv
		# The property will not exist (NULL) for characters not present in the list
		cypher = "
		LOAD CSV WITH HEADERS FROM '#{char_ranks_url}' as line
		FIELDTERMINATOR '\t' 
		WITH line.character as char, toInt(line.rank) as rank
		MATCH (ch:Character{simp: char})
		SET ch.freq_rank = rank"
		@neo.execute_query(cypher)
	end

	def link_characters_to_radicals(char_radicals_url)
		cypher = "
		LOAD CSV WITH HEADERS FROM '#{char_radicals_url}' as line
		WITH split(line.radicals, ';') as radicals, line.character as char_simp 
		UNWIND radicals as radical
		WITH trim(radical) as radical_simp, char_simp
		MATCH (rd:Radical{simp: radical_simp})
		MATCH (ch:Character{simp: char_simp})
		CREATE UNIQUE (ch)-[:HAS_RADICAL]->(rd)"
		@neo.execute_query(cypher)
	end


	# backbone
	def add_backbone(backbone_url)
		cypher = "
		LOAD CSV WITH HEADERS FROM '#{backbone_url}' as line
		WITH trim(toString(line.char_id)) as b_id, trim(line.char) as simp, split(line.formula,'+') as parts
		MERGE (b:Backbone{backbone_id: b_id}) SET b.simp = simp
		//connect the part-of nodes
		WITH parts, b_id, b, simp
		UNWIND parts as part
		MATCH (part_node:Backbone{backbone_id: trim(part)})
		CREATE UNIQUE (part_node)-[:PART_OF]->(b)"
		@neo.execute_query(cypher)

		# Link radicals
		cypher = "
		MATCH (b:Backbone)
		MATCH (rad:Radical{simp: b.simp})
		CREATE UNIQUE (b)-[:IS_RADICAL]->(rad)"
		@neo.execute_query(cypher)

		# Link words
		cypher = "
		MATCH (b:Backbone)
		MATCH (w:Word{simp: b.simp})
		CREATE UNIQUE (b)-[:IS_WORD]->(w)"
		@neo.execute_query(cypher)

		# Link characters
		cypher = "
		MATCH (b:Backbone)
		MATCH (ch:Character{simp: b.simp})
		CREATE UNIQUE (b)-[:IS_CHARACTER]->(ch)"
		@neo.execute_query(cypher)

		# Create a linked list of ordered nodes
		cypher = "
		MATCH (b:Backbone)
		WHERE toInt(b.backbone_id) IS NOT NULL
		WITH toInt(b.backbone_id) as b_id, toInt(b.backbone_id) + 1 as next_id
		MATCH (from:Backbone{backbone_id: toString(b_id)})
		MATCH (to:Backbone{backbone_id: toString(next_id)})
		CREATE UNIQUE (from)-[:NEXT]->(to)"
		@neo.execute_query(cypher)
	end

	#### 
	# Generic 
	#
	def count_nodes
		result = @neo.execute_query("MATCH (n) RETURN count(n) as count")
		result["data"][0][0]
	end

	def clean
		# Delete all nodes and relationships in the DB
		@neo.execute_query("MATCH (n) DETACH DELETE n")
	end

	def run_cypher(cypher) 
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end

	#### 
	# Queries for tests
	#
	def find_pinyin_block(block)
		cypher = "
		MATCH (b:PinyinBlock{block: '#{block}'}) 
		RETURN b.block as block, b.vow as vow, b.cons as cons"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)[0]
	end

	def find_radical(simp)
		cypher = "
		MATCH (r:Radical{simp: '#{simp}'}) 
		RETURN r.simp as simp"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)[0]
	end

	#### 
	# Queries for views
	#
	# Index
	#  all pending testing
	def words(username)
		cypher = "
		MATCH (:Person {name:'#{username}'})-[rel]->(w:Word) 
		RETURN w.hsk as level, 
					 w.simp as simp,
					 w.unique as word_unique,
					 w.pinyin_tonemarks as pinyin,
					 type(rel) as rel,
					 rel.date as date
		ORDER BY date DESC, rel, level"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph).map do |h| 
			h[:date] = format_timestamp(h[:date])
			h
		end
	end
	def words_top(username, relationship, top_size)
		# Some words will not be connected to the backbone yet, 
		# but they will later on as the backbone grows
		cypher = "MATCH (:Person {name:'#{username}'})-[rel:#{relationship}]->(w:Word) 
							MATCH (ch:Character)<-[:HAS_CHARACTER]-(w)-[:HAS_PINYIN]->(pw:PinyinWord)
						  MATCH (b:Backbone)-[:IS_CHARACTER]->(ch)
							RETURN type(rel) as word_rel, 
										 w.hsk as level,
										 w.unique as word_unique,
										 w.simp as simp,
										 pw.pinyin_tm as pinyin,
										 collect(b.backbone_id)[0] as backbone_id
							ORDER BY level, length(word_unique), toInt(backbone_id)
							LIMIT #{top_size}"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end

	def words_last_timestamp(username, relationship)
		cypher = "MATCH (u:Person {name:'#{username}'})-[rel:#{relationship}]->(w:Word) 
		          RETURN w.simp, rel.date
							ORDER BY rel.date DESC
							LIMIT 1"
		graph = @neo.execute_query(cypher)
	  simp, timestamp = graph["data"].first # because we know we limit 1
		date = format_timestamp(timestamp)
		[simp, date]
	end

	def word_user_counts(user)
		# Independently of the backbone, how many other words are related to a given character?
		cypher = "MATCH (p:Person{name: '#{user}'})-[rel]->(w:Word)
							RETURN type(rel) as rel, 
										 w.hsk as level,
										 count(w.unique) as count"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end
	def word_bb_counts
		# Independently of the user, how many other words are related to the backbone?
		cypher = "MATCH (w:Word)-[:HAS_CHARACTER]->(:Character)<-[:IS_CHARACTER]-(b:Backbone)
						  RETURN count(DISTINCT w.unique) as count,
										 w.hsk as level
							ORDER BY level"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end
	def characters_connected(in_backbone=true)
		# words of length == 1
		# How many characters (words of size 1) are present/absent in the backbone
		cond = in_backbone ? '' : 'NOT'
		cypher = "MATCH (w:Word) 
						  WHERE #{cond} (w)<-[:IS_WORD]-(:Backbone) AND length(w.simp) = 1
							RETURN count(DISTINCT w.simp) as count, 
										 w.hsk as level
							ORDER BY level"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end

	# Tones
	def words_grouped_by_tones(username)
		cypher = "MATCH (:Person {name:'#{username}'})-[rel]->(w:Word)-[:HAS_TONE]->(t:ToneCombo) 
							RETURN count(w.simp) AS num, 
                     collect(w.simp) AS words, 
										 collect (type(rel)) AS states, 
                     t.tone 
							ORDER BY num DESC"
		graph = @neo.execute_query(cypher)
		triplets = graph["data"]

		# pass the state of the word together with the word
		edited_triplets = []
		triplets.each do |t|
			num, words, states, tone = t 
			words_by_state = Hash[states.uniq.map{|s|[s,[]]}]
			words.zip(states).each do |word, state|
				words_by_state[state] << word
			end
			edited_triplets << [num, words_by_state, tone]
		end
		edited_triplets
	end

	def word_details(username, word_unique)
		# in some cases we are passing a non-sense word_unique (as the id)
		return {} if word_unique.numeric?

		# Return all details for a single word
		cypher = "MATCH (:Person{name:'#{username}'})-[r]->(w:Word{unique:'#{word_unique}'})
							MATCH  (w)-[:HAS_PINYIN]->(p:PinyinWord)
							RETURN	type(r) as rel, 
											w.simp as simp, 
											w.eng as eng, 
										  w.hsk as level,
											p.pinyin_tm as pinyin"

		graph = @neo.execute_query(cypher)
		word = records_to_hashes(graph).first
		word[:word_unique] = word_unique

		# Return the radicals and backbone related to each char in the word
		cypher = "MATCH (:Person{name:'#{username}'})-->(w:Word{unique:'#{word_unique}'})
							MATCH  (w)-[:HAS_CHARACTER]->(ch:Character)
							OPTIONAL MATCH  (b)-[:IS_CHARACTER]->(ch)
							OPTIONAL MATCH  (ch)-[:HAS_RADICAL]->(r:Radical)
							RETURN	ch.simp as char, 
											collect(r.simp) as radicals, 
		                  b.backbone_id as backbone_id"
		graph = @neo.execute_query(cypher)
		chars = records_to_hashes(graph)

		# hash the chars by character for easier manipulation
		word[:chars] = Hash[chars.map{|h| [h[:char], h]}]

		word
	end

	# Backbone
	def backbone(username)
		cypher="MATCH (b:Backbone)-[:NEXT]->(:Backbone)
						OPTIONAL MATCH (b)-[:IS_WORD]->(w:Word)<-[rel]-(:Person{name:'#{username}'})
						OPTIONAL MATCH (b)-[:IS_CHARACTER]->(ch:Character)
						RETURN b.backbone_id as backbone_id, 
									 b.simp as simp, 
									 collect(w.unique) as words_unique, 
									 collect(type(rel)) as words_rel,
									 ch.freq_rank as char_freq_rank
						ORDER BY toInt(backbone_id)"

		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end

	def backbone_node(username, bid)
		# composites
		cypher = "MATCH (ch)<-[:IS_CHARACTER]-(b:Backbone{backbone_id:'#{bid}'})
							MATCH (b)-[:PART_OF]->(composite:Backbone)
							RETURN composite.simp as simp, 
										 composite.backbone_id as backbone_id"
		graph = @neo.execute_query(cypher)
		composites = records_to_hashes(graph)

		# parts and char_simp 
		cypher = "MATCH (ch)<-[:IS_CHARACTER]-(b:Backbone{backbone_id:'#{bid}'})
							OPTIONAL MATCH (b)<-[:PART_OF]-(part:Backbone)
							RETURN ch.simp, ch.freq_rank, part.simp, part.backbone_id"
		graph = @neo.execute_query(cypher)
		if graph["data"][0].nil?
			# special case where there are no words that contain the character 
			char_simp = ''
			freq_rank = -1
			parts = []
			words = []
			return {backbone_id: bid, simp: char_simp, freq_rank: freq_rank, parts: parts, composites: composites, words: words}
		else
			char_simp  = graph["data"][0][0]
			freq_rank  = graph["data"][0][1]
			parts = graph["data"].map {|r| {simp: r[2], backbone_id: r[3]}}
			parts = parts.select{|p| p[:simp] != char_simp} unless parts.empty?
			parts = [] if parts.size == 1 && parts.first[:simp].nil? 
		end

		# words
		cypher = "MATCH (ch)<-[:IS_CHARACTER]-(b:Backbone{backbone_id:'#{bid}'})
							MATCH (ch)<-[:HAS_CHARACTER]-(w:Word)<-[rel]-(:Person{name:'#{username}'})
							RETURN w.unique as word_unique, 
										 w.simp as word_simp, 
										 type(rel) as word_rel, 
										 w.hsk as level
							ORDER BY level, length(word_simp)"
		graph = @neo.execute_query(cypher)
		words = records_to_hashes(graph)

		# all together
		{backbone_id: bid, simp: char_simp, freq_rank: freq_rank, parts: parts, composites: composites, words: words}
	end

	# Knowledge
	def update_known_relationship(username, word_unique, r_old, r_new)
		# remove one relationship and substitute it for the new status
		cypher = "MATCH (:Person {name:'#{username}'})-[r:#{r_old}]->(w:Word{unique:'#{word_unique}'}) DELETE r"
		@neo.execute_query(cypher)
		cypher = "MATCH (u:Person {name:'#{username}'}), (w:Word {unique:'#{word_unique}'})
							CREATE UNIQUE (u)-[:#{r_new}{date: TIMESTAMP()}]->(w)"
		@neo.execute_query(cypher)
	end

	private
	def format_timestamp(timestamp)
		#Time.at((timestamp.to_f / 1000).to_i).strftime("%Y-%m-%d %H:%M:%S")
		Time.at((timestamp.to_f / 1000).to_i).strftime("%Y-%m-%d")
	end
	def records_to_hashes(graph)
		# Converts a list of result records into a list of hashes
		headers = graph["columns"]
		graph["data"].map do |r|
			Hash[headers.each_with_index.map{|col, i| [col.to_sym, r[i]]}]
		end
	end

	def export(filename, cypher)
		graph = @neo.execute_query(cypher)
		CSV.open(filename, "w") do |csv|
			csv << graph["columns"]
			graph["data"].each {|d| csv << d}
		end
	end

end
