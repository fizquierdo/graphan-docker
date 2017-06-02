require_relative '../neo4j_api'

# Import data into DEV
data_url = "https://raw.githubusercontent.com/fizquierdo/graphan-docker/master/app/data/"

neo = Neo4j.new({"port" => 7474, "server" => "localhost"})

puts "Deleting previous DB"
neo.clean
puts "Creating Pinyin Blocks"
neo.add_pinyin_blocks("data/pinyinchart.csv")
puts "Adding radical list"
neo.add_radicals("data/radical_list.csv")

# Words
puts "Importing words"
neo.import_words(data_url+"hsk_words.tsv")

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
neo.add_freq_rank_to_characters(data_url+"character_frequency.tsv")
puts "Add character decomposition to character"
neo.link_characters_to_radicals(data_url+"hsk_radicals.csv")

# Backbone
puts "Add backbone nodes"
neo.add_backbone(data_url+"backbone.csv")

## Import existing user data
#puts "Importing user data"
#neo.import_users("data/exports/user_db.csv")
#puts "Importing user data rels"
#neo.import_users_rels("data/exports/user_db_rels.csv")
