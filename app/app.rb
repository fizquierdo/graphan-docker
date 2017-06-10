require 'sinatra'
require 'sinatra/flash'
require_relative 'neo4j_api'
require_relative 'lib/user'
require_relative 'lib/panel'

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
# Accesss control for logged users
#
register do 
	def auth(type)
		# add a condition to the route
		condition do 
			redirect "/" unless send("is_#{type}?")
		end
	end
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
	def is_user?
		@username != "unlogged-user"
	end
	def is_admin?
		@username == "admin"
	end
	def backbone_window(backbone, backbone_id, window_size=3)
		start_offset = 1
		idx = backbone_id.to_i - 1 - start_offset
		prev_idx = [0, idx-window_size].max + 1
		post_idx = [backbone.size-1, idx+window_size].min
		return backbone[prev_idx..post_idx]
	end

	def order_chars_from_word_details(word_details)
		ordered_chars = []
		word_details[:simp].split(//).each do |char|
				radicals    = word_details[:chars][char][:radicals]
				backbone_id = word_details[:chars][char][:backbone_id]
				ordered_chars << [char, radicals, backbone_id] 
		end
		ordered_chars
	end

	def build_tonepair_matrix(quartets)
		# Decompose the quartets into a tone pairs matrix
		# First tones (rows) range from 1 to 4
		# Second tones (cols) range from 1 to 5 to include neutral tone endings
		tone_pairs = quartets.select{ |_, _, _, tone| tone.size == 2 }
		tone_matrix = Hash[1.upto(4).map{|n| [n.to_s,Hash[1.upto(5).map{|x| [x.to_s,{}]}]]}]
		tone_pairs.each do |_, known, learning, tone|
			first, second = tone.split('')
			tone_matrix[first][second] = {known: known[0..1], learning: learning[0..1]}
		end
		tone_matrix
	end

	def escaped_query(params)
		URI.escape(params.map{|k, v| "#{k}=#{v}"}.join('&'))
	end
end

def get_top_recommendations(graphan, username)
	tops = {}
	%w(LEARNING IGNORES).each do |state|
		tops[state] = {top1: {}, top5: []}
		top5 = graphan.words_top(username, state, 5)
		tops[state][:top5] = top5
		tops[state][:top1] = top5.first unless top5.empty?
	end
	tops
end

###
# App 
#

before do
	@username = get_username
end

###
# App - auth
#
get '/signin/?' do 
	erb :signin
end

post '/signin/?' do 
	# get hash in graphan for current username
	# assumes 1 user with that name, and user has a hash 
	# we will not find any hash for a non-existing user
	users = graphan.get_users(params[:username])
	if users.empty? 
		hash = nil
	else
		hash = users.first[:hash]
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
	session[:user] = nil
	flash[:notice] = 'You have been signed out.'
	redirect '/'
end

####
# App - graphan


get '/' do
	# Last activity
	@learning_simp, @learning_date = graphan.words_last_timestamp(@username, 'LEARNING')
	@known_simp, @known_date = graphan.words_last_timestamp(@username, 'KNOWS')

	# User counts
	panel = Panel.new graphan.word_user_counts(@username)
	@count_headings, @count_rows = panel.counts_table

	# Recommendations
	@tops = get_top_recommendations(graphan, @username)

	# Backbone state (this info is independent of the user, just shows bb-quality)
	if is_admin?
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

get '/tonelist', :auth => :user do 
	triplets = graphan.words_grouped_by_tones(@username)
	@quartets = triplets.map do |num, words, tone|
		known_words = words["KNOWS"] || []
		learning_words = words["LEARNING"] || []
		[num, known_words, learning_words, tone]
	end
	@tonepair_matrix = build_tonepair_matrix(@quartets)

	erb :tonelist
end

# Show a list of all words, could show for unlogged-user
get '/words', :auth => :user do 
	@words = graphan.words(@username)
	erb :words
end

# Backbone
get '/backbone_node', :auth => :user do 
	raise "Missing backbone_id in #{params}" unless params["backbone_id"]

	@backbone_node   = graphan.backbone_node(@username, params["backbone_id"])
	@backbone_window = backbone_window(graphan.backbone(@username), params["backbone_id"])
	@learning_top = graphan.words_top(@username, 'LEARNING', 5)
	@ignores_top  = graphan.words_top(@username, 'IGNORES', 5)
	if params["word_unique"]
		@word_details  = graphan.word_details(@username, params["word_unique"])
		@ordered_chars = order_chars_from_word_details(@word_details)
	else
		@word_details  = []
	end
	erb :backbone_node
end

# Backbone is available to be seen for an unlogged-user
get '/backbone' do 
	@backbone = graphan.backbone(@username)
	erb :backbone
end

# in backbone
post '/learning_word' do
	graphan.update_known_relationship(session[:user], params["word_unique"], 'IGNORES', 'LEARNING')
	redirect to("/backbone_node?#{escaped_query(params)}")
end
post '/learnt_word' do
	graphan.update_known_relationship(session[:user], params["word_unique"], 'LEARNING', 'KNOWS')
	redirect to("/backbone_node?#{escaped_query(params)}")
end
post '/forgot_word' do
	graphan.update_known_relationship(session[:user], params["word_unique"], 'KNOWS', 'LEARNING')
	redirect to("/backbone_node?#{escaped_query(params)}")
end

# in home
get '/follow_recommendation', :auth => :user do
	redirect to("/backbone_node?#{escaped_query(params)}")
end
