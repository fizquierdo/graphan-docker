require 'neography'
require "csv"

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

	#### import 
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
						note = note.gsub(')','').strip
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

	#### generic 

	def count_nodes
		result = @neo.execute_query("MATCH (n) RETURN count(n) as count")
		result["data"][0][0]
	end

	def clean
		# Delete all nodes and relationships in the DB
		@neo.execute_query("MATCH (n) DETACH DELETE n")
	end

	#### finders and executers (could be generic?)
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
	def run_cypher(cypher) 
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)
	end


	private
	def records_to_hashes(graph)
		# Converts a list of result records into a list of hashes
		headers = graph["columns"]
		graph["data"].map do |r|
			Hash[headers.each_with_index.map{|col, i| [col.to_sym, r[i]]}]
		end
	end

end
