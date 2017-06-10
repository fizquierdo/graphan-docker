require_relative '../../neo4j_api'

cfg_file = File.join(File.dirname(__FILE__), '../../config/prod/config.yml')
config = YAML.load_file(cfg_file)
neo = Neo4j.new(config)

export_dir = File.join(File.dirname(__FILE__), '../../data/exports')
puts "Exporting DB user data to folder #{export_dir}"

fname = File.join(export_dir, 'user_db.csv')
neo.export_users(fname)

fname = File.join(export_dir, 'user_db_rels.csv')
neo.export_users_rels(fname)
