require 'spec_helper'
require 'rack/test'
require_relative '../app'

ENV['RACK_ENV'] = nil  

describe "neo4j app" do

	include Rack::Test::Methods
	def app
		Sinatra::Application
	end

	it 'Neo4j test page loads' do
		get '/'
		expect(last_response.body).to include('Neo4j')
	end

end
