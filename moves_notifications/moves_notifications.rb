require 'rubygems'
require 'bundler'

Bundler.require(:default, ENV['RACK_ENV'])
require File.expand_path('../../moves_app/models', __FILE__)


class ProcessDay
  @queue = :process_day
  
  def self.perform(moves_user_id, day)
    user = User.find(moves_user_id)
  end
end



class MovesNotifications < Sinatra::Base
  
  post '/' do
  	s = env['HTTP_X_MOVES_SIGNATURE']
  	t = env['HTTP_X_MOVES_TIMESTAMP']
  	n = env['HTTP_X_MOVES_NONCE']
  	b = request.body.read.to_s

  	calculated_sig = Base64.encode64("#{OpenSSL::HMAC.digest('sha1',ENV['MOVES_CLIENT_SECRET'], [b,t,n].join(''))}").chomp

    if s != calculated_sig
      halt 403, "Incorrect signature"
    end

    body_json = Object.new
    begin
      body_json = JSON.parse(b)
    rescue JSON::ParserError => e
      puts "JSON Parser Error: #{e.message}"
      halt 500, "JSON Parser Error"
    end

    moves_user_id = nil
    begin
      moves_user_id = body_json['userId']
      raise "NoUserId" unless moves_user_id
    rescue Exception => e
      puts "User not found in JSON: #{e.message}"
      halt 500, "User not found in JSON"
    end
    moves_user_id = moves_user_id.to_s
    
    begin
      
      body_json['storylineUpdates'].each do | update |
        next if update['reason'] == 'PlaceRename' or update['reason'] == 'PlaceUpdate'
        start_time = DateTime.strptime(update['startTime'],"%Y%m%dT%H%M%S%z").to_date
        end_time = DateTime.strptime(update['endTime'],"%Y%m%dT%H%M%S%z").to_date
        (start_time..end_time).each do |date|
          puts "Queuing #{date} for user #{moves_user_id}"
          Resque.enqueue(ProcessDay, moves_user_id , date.to_s)
        end
      end
    rescue Exception => e
      puts "Error extracting data: #{e.message}"
      halt 500, "Error extracting data"
    end
    
  	200
  end

end
