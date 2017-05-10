require 'sinatra'
require_relative 'neo4j_api'

cfg_file="/home/app/config.yml" # Expects to be mounted in the docker container
unless File.exist? cfg_file
	# when not running with docker just use DEV config file (automated tests)
	cfg_file = File.join(File.dirname(__FILE__), 'config/dev/config.yml') 
end
config = YAML.load_file(cfg_file)
db = Neo4j.new(config)

get '/' do
	@num_nodes = db.count_nodes
	erb :index
end
