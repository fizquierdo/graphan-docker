require_relative '../neo4j_api'

# Import data into DEV
neo = Neo4j.new({"port" => 7474, "server" => "localhost"})

puts "Deleting previous DB"
neo.clean
puts "Creating Pinyin Blocks"
neo.add_pinyin_blocks("data/pinyinchart.csv")
#puts "Adding radical list"
#neo.add_radicals("data/radical_list.csv")

# Words
puts "Importing words"
words_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/data/hsk_words.tsv"
neo.import_words(words_url)

# Pinyin
puts "Linking pinyin blocks"
neo.link_words_with_pinyin_blocks
puts "Creating pinyin nodes"
neo.create_pinyin_from_words
puts "Creating tone combos from words"
neo.create_tone_combos_from_words

# Characters
puts "Create character nodes from words"
neo.create_characters_from_words
puts "Add frequency to characters"
puts "Connect characters to radical"
