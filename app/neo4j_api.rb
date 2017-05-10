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

	#### generic 

	def count_nodes
		result = @neo.execute_query("MATCH (n) RETURN count(n) as count")
		result["data"][0][0]
	end

	def clean
		# Delete all nodes and relationships in the DB
		@neo.execute_query("MATCH (n) DETACH DELETE n")
	end

	#### finders (could be generic?)
	def find_pinyin_block(block)
		cypher = "MATCH (b:PinyinBlock{block: '#{block}'}) 
							RETURN b.block as block, b.vow as vow, b.cons as cons"
		graph = @neo.execute_query(cypher)
		records_to_hashes(graph)[0]
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
