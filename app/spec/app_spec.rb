ENV['RACK_ENV'] = nil  

require 'spec_helper'
require 'rack/test'
require_relative '../app'

describe "Sinatra app" do

	include Rack::Test::Methods
	def app
		Sinatra::Application
	end

	it 'Index page loads' do
		get '/'
		expect(last_response.body).to include('Home')
	end

end
