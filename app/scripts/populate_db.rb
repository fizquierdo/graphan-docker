require_relative '../neo4j_api'

# Import data into DEV
neo = Neo4j.new({"port" => 7474, "server" => "localhost"})

puts "Deleting previous DB"
neo.clean
puts "Creating Pinyin Blocks"
neo.add_pinyin_blocks("data/pinyinchart.csv")
