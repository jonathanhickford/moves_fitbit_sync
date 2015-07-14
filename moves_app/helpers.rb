module MovesHelpers
	def fitbit_client_for_user(user)
		fitbit = Fitgem::Client.new ({
        :consumer_key => ENV['FITBIT_CLIENT_ID'],
        :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
        :token => user.fitbit_account.access_token,
        :secret => user.fitbit_account.secret_token,
        :unit_system => Fitgem::ApiUnitSystem.METRIC
      })
		fitbit.reconnect(user.fitbit_account.access_token, user.fitbit_account.secret_token)
      fitbit
	end

	def moves_client_for_user(user)
		moves_token = user.moves_account.access_token
     	moves = Moves::Client.new(moves_token)
     end

end
