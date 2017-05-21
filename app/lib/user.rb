require 'bcrypt'

class User
	include BCrypt

	def initialize
	end

	def self.create(params={})
		return nil if params[:username].empty? || params[:password].empty? 
		{name: params[:username], hash: Password.create(params[:password]).to_s}
	end

	def self.authenticate(hash, params={})
		# params should have keys :username and :password
		# Returns username if password correct, nil otherwise
		return nil if params[:username].empty? || params[:password].empty? || hash.nil?

		# Check if the secret matches the stored hash
		if Password.new(hash) == params[:password]
			return params[:username]
		else
			return nil
		end
	end
end
