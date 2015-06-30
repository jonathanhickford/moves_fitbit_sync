require 'rubygems'
require 'bundler'
require 'pp'
require 'base64'
require 'openssl'

Bundler.require

class MovesNotifications < Sinatra::Base
  
  configure do
  end

  configure :development do
    register Sinatra::Reloader
  end

  post '/' do
  	s = env['HTTP_X_MOVES_SIGNATURE']
  	t = env['HTTP_X_MOVES_TIMESTAMP']
  	n = env['HTTP_X_MOVES_NONCE']
  	b = request.body

  	message = [b,t,n].join('|')
  	calculated_sig = Base64.encode64("#{OpenSSL::HMAC.digest('sha1',ENV['MOVES_CLIENT_SECRET'], message)}").chomp
  	data = {
  		:signature => s,
  		:calculated_sig => calculated_sig,
  		:timestamp => t,
  		:nonce => n,
  		:request_body => b
  	}
  	puts data
  	[200, data.to_json]
  end

end
