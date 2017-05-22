require 'sinatra'
require 'sinatra/flash'
require_relative 'neo4j_api'
require_relative 'lib/user'

###
# Config
#

TWENTY_MINUTES = 60 * 20
use Rack::Session::Pool, expire_after: TWENTY_MINUTES # Expire sessions after 20 minutes of inactivity

cfg_file="/home/app/config.yml" # Expects to be mounted in the docker container
unless File.exist? cfg_file
	# when not running with docker just use DEV config file (automated tests)
	cfg_file = File.join(File.dirname(__FILE__), 'config/dev/config.yml') 
end
config = YAML.load_file(cfg_file)
graphan = Neo4j.new(config)

enable :logging
before do
	    logger.level = Logger::DEBUG
end

###
# Helpers
#

helpers do 
	def get_username
		username = session[:user] || "unlogged-user"
		logger.debug "CURRENT user #{username}"
		username
	end
end

###
# auth
#
get '/signin/?' do 
	erb :signin
end

post '/signin/?' do 
	# get hash in graphan for current username
	# assumes 1 user with that name, and user has a hash 
	# we will not find any hash for a non-existing user
	users = graphan.get_users(params[:username])
	if users.size != 1
		hash = nil
	else
		hash = users.first["hash"]
	end
	
	# check if password entered is correct and return username 
	user = User.authenticate(hash, params)
	if user.nil? 
		flash[:notice] = 'Sign in failed.' 
	  logger.debug "loading msg  #{flash[:notice]}"
		redirect '/signin'
	else
		session[:user] = user
		flash[:notice] = "Welcome back #{session[:user]}"
		redirect '/'
	end
end

get '/signup/?' do 
	erb :signup
end

post '/signup/?' do 
	# check if name is already taken
	users = graphan.get_users(params[:username])
	if params[:username] and not users.empty?
		flash[:notice] = "Username #{params[:username]} already taken." 
		redirect '/signup'
	end

	# Create a new user if name and password are available
	user = User.create(params)
	if user.nil? 
		flash[:notice] = 'Sign up failed.' 
		redirect '/signup'
	else
		flash[:notice] = "Registering new user #{user[:name]}"
		graphan.create_user(user) 
		session[:user] = user[:name]
		flash[:notice] = "Welcome #{session[:user]}"
		redirect '/'
	end
end

get '/signout' do
	# TODO implement this as a link/button so that it runs on-click
	session[:user] = nil
	flash[:notice] = 'You have been signed out.'
	redirect '/'
end

####
# App

get '/' do
	@username = get_username

	## TODO think what would be a good summary 
	states = {}
	%w(KNOWS LEARNING IGNORES).each do |state|
		states[state] = graphan.words_last_timestamp(@username, state)
	end
	@learning_simp = states['LEARNING'][0]
	@learning_date = states['LEARNING'][1]
	@known_simp = states['KNOWS'][0]
	@known_date = states['KNOWS'][1]

	panel = Panel.new graphan.word_user_counts(@username)
	@count_headings, @count_rows = panel.counts_table

	# Recommendations
	top_size = 5
	@learning_top = graphan.words_top(@username, 'LEARNING', top_size)
	@ignores_top  = graphan.words_top(@username, 'IGNORES', top_size)

	# Backbone state (this info is independent of the user, just shows bb-quality)
	if @username == 'admin'
		disconn= graphan.characters_connected(false)
		connect= graphan.characters_connected(true)
		word_bb_counts = graphan.word_bb_counts
		@bb_headings, @bb_rows = panel.backbone_table(disconn, connect, word_bb_counts)
		@display_bb = true
	else
		@display_bb = false
	end

	erb :index
end
