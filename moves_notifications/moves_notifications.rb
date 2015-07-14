require 'rubygems'
require 'bundler'

Bundler.require(:default, ENV['RACK_ENV'])
require File.expand_path('../../moves_app/models', __FILE__)
require File.expand_path('../../moves_app/helpers', __FILE__)


class ProcessDay
  include MovesHelpers
  @queue = :process_day
  
  def self.perform(moves_user_id, day)
    user = User.find(moves_user_id)
    date = Date.strptime(day, '%Y-%m-%d')

    puts "Process #{user.name} for #{date}"
    moves = moves_client_for_user(user)
    fitbit = fitbit_client_for_user(user)

    fitbit_data = fitbit.activities_on_date date
    fitbit_rides = BikeRide.rides_from_fitbit(fitbit_data)
    
    moves_data = moves.daily_activities(date)
    moves_rides = BikeRide.rides_from_moves(moves_data)
    
    cycle_data = BikeRide.merge_rides(fitbit_rides, moves_rides)
    BikeRide.select_moves_rides(cycle_data).each do | time, ride |
      puts "Logging ride to fitbit: #{ride}"
      ride.log_to_fitbit(fitbit)
    end
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
