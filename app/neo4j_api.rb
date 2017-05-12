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


	#### import 
	def add_pinyin_blocks(filename)
		# Add all possible pinyin sounds from a table file in csv format
		pinyin = CSV.read(filename, headers: true)
		py_chart_blocks = {}

		vowels = pinyin.headers - ["cons"]
		pinyin.each do |p|
			cons = p["cons"] || 'No-Cons'
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
		cypher = "MATCH (b:PinyinBlock{block: '#{block}'}) 
							RETURN b.block as block, b.vow as vow, b.cons as cons"
							graph = @neo.execute_query(cypher)
							records_to_hashes(graph)[0]
	end
	def find_radical(simp)
		cypher = "MATCH (r:Radical{simp: '#{simp}'}) 
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
