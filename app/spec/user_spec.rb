ENV['RACK_ENV'] = nil  

require 'spec_helper'
require 'rack/test'
require_relative '../lib/user'

describe "User password encription" do

	describe "User creation" do

		it 'avoids password creation if not enough info avalable' do
			ret = User.create({username: 'Bob', password: ''})
			expect(ret).to be_nil
			ret = User.create({username: '', password: 'secret'})
			expect(ret).to be_nil
		end

		it 'creates a password' do
			ret = User.create({username: 'Bob', password: 'secret'})
			expect(ret[:name]).to eq('Bob')
			expect(ret[:hash]).not_to eq('secret')
		end

	end


	describe "User authentication" do
		before(:each) do
			@user_params = {username: 'Bob', password: 'secret'}
			@user = User.create(@user_params)
		end

		it 'returns username if correct username/password is passed' do
			name = User.authenticate(@user[:hash], @user_params)
			expect(name).to eq('Bob')
		end

		it 'returns nil if wrong password is passed' do
			wrong_params = {username: 'Bob', password: 'wrong_secret'}
			name = User.authenticate(@user[:hash], wrong_params)
			expect(name).to be_nil
		end

	end
end
