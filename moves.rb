require 'rubygems'
require 'bundler/setup'

require 'omniauth'
require 'omniauth-moves'
require 'moves'
require 'json'

client_secrets = JSON.parse(File.read('client_secrets.json'))

use OmniAuth::Builder do
  provider :moves, client_secrets['client_id'], client_secrets['client_secret']
end

moves = Moves::Client.new(access_token)


moves.daily_activities
