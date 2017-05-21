ENV['RACK_ENV'] = nil  

require 'spec_helper'
require 'rack/test'
require_relative '../app'

describe "Sinatra app" do

	include Rack::Test::Methods
	def app
		Sinatra::Application
	end

	# Index
	describe "Home page" do
		it 'Home page loads' do
			get '/'
			expect(last_response.body).to include('Home')
		end
		it 'welcomes user if signed in' do
			get '/', :username => 'Bob'
			expect(last_response.body).to include('Hello Bob')
		end
		it 'Tells user to sign in if not logged-in' do
			get '/', :username => 'unlogged-user'
			expect(last_response.body).to include('Sign in if you have an account')
		end
	end

	# Sign up
	describe "Sign up page" do
		it 'Signup page loads' do
			get '/signup'
			expect(last_response.body).to include('Sign Up for a new account')
		end
	end

	# Sign in
	it 'Signin page loads' do
		get '/signin'
		expect(last_response.body).to include('Sign in')
		expect(last_response.body).to include('Username')
	end

	it 'does not signin a wrong user' do
		post '/signin', {username: "idontexist", password: "not-a-pass"}
		expect(last_response.body).to include('Sign in failed')
		expect(last_request.path).to eq('/signin')
	end

end
