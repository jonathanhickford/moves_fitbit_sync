require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require "sinatra/reloader"
require 'omniauth'

require 'omniauth'
require 'omniauth-moves'
require 'omniauth-fitbit'
require 'moves'
require 'fitgem'
require 'json'

require 'mongoid'

FITBIT_BIKE_RIDE_PARENT_ID = 90001

require File.expand_path('../app/models', __FILE__)

class MovesApp < Sinatra::Base
  
  configure do
    set :sessions, true
    set :inline_templates, true
    Mongoid.load!("./mongoid.yml")
  end

  configure :development do
    register Sinatra::Reloader
  end

  use OmniAuth::Builder do
    provider :moves, ENV['MOVES_CLIENT_ID'], ENV['MOVES_CLIENT_SECRET']
    provider :fitbit, ENV['FITBIT_CLIENT_ID'], ENV['FITBIT_CLIENT_SECRET']
  end

  helpers do
    def render_rides(rides)
     @rides = rides
     erb "
     <% @rides.each do |ride| %>
      <p>
        <span>Date: <%= ride.date %> </span>
        <span>Start Time: <%= ride.startTime %> - </span>
        <span>Duration: <%= ride.duration %> ms</span>
        <span>Distance: <%= ride.distance %> km</span>
      </p>
    <% end %>
    "
    end

    def render_rides_with_logging(rides)
     @rides = rides
     erb "
     <% @rides.each do |ride| %>
      <p>
        <span>Date: <%= ride.date %> </span>
        <span>Start Time: <%= ride.startTime %> - </span>
        <span>Duration: <%= ride.duration %> ms</span>
        <span>Distance: <%= ride.distance %> km</span>
        <span><%= log_ride_to_fitbit_link(ride) %></span

      </p>
    <% end %>
    "
    end

    def log_ride_to_fitbit_link(ride)
      @ride = ride
      erb "
        <button onclick=\"event.preventDefault(); $.post( '/fitbit/log_activity', { activity_id: '<%= BikeRide.activityId%>', duration: '<%= @ride.duration %>' , distance: '<%= @ride.distance %>', start_time: '<%= @ride.startTime %>', start_date: '<%= @ride.date %>'} );\">Log</button>
      "
    end

  end

   before '*/summary/:date' do
    begin
      @date = Date.strptime(params['date'], '%Y-%m-%d')
    rescue  
      halt 404, "bad date"
    end
   end




  get '/' do
    redirect '/select_user' unless session['user_id']

    @user = User.find(session['user_id'])

    erb :index
  end

  get '/select_user' do
    erb "
      <p>Select a user:</p>
      <form action='/select_user' method='POST'>
        <input type='hidden' name='_method' value='POST'/>
        <ul>  
          <% User.each do | user | %>
            <li><input type='radio' name ='id' value='<%= user.id %>'/><%= user.name %></li>
          <% end %>
        </ul>
        <input type='submit' name='submit' value='Select'/>
      </form>
    "
  end

  post '/select_user' do
    puts params['id']
    session[:user_id] = User.find(params['id'])
    redirect '/'
  end


  get '/register' do
    user = User.new
    erb "
    <form action='/user' method='POST'>
        <input type='hidden' name='_method' value='POST'/>
        <input type='text' name ='user[name]'/>
        <input type='submit' name='submit' value='Save'/>
      </form>
    "
  end

  post '/user' do
    user = User.new(params[:user])
    if user.save
      redirect '/'
    else
      "Error saving user"
    end
  end


  get '/link_accounts' do
    erb :link_accounts
  end

  get '/auth/:provider/callback' do
    auth = request.env['omniauth.auth']
    
    if params[:provider] == "moves"
      user = User.find(session['user_id'])
      user.moves_account = MovesAccount.new(
        uid: auth['uid'],
        access_token: auth['credentials']['token'],
        refresh_token: auth['credentials']['refresh_token'],
        expires_at: Time.at(auth['credentials']['expires_at'])
      )
      user.save
    elsif params[:provider] == "fitbit"
      user = User.find(session['user_id'])
      user.fitbit_account = FitbitAccount.new(
        uid: auth['uid'],
        access_token: auth['credentials']['token'],
        secret_token: auth['credentials']['secret'],
      )
      user.save
    end

    erb "<h1>#{params[:provider]}</h1>
         <pre>#{params}</pre>"
  end
  
  get '/auth/failure' do
    erb "<h1>Authentication Failed:</h1><h3>message:<h3><pre>#{params}</pre>"
  end

  
  get '/moves/summary/?' do
    redirect "moves/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end

  get '/moves/summary/:date' do

    user = User.find(session['user_id'])
    moves_token = user.moves_account.access_token
    moves = Moves::Client.new(moves_token)

    @data = moves.daily_activities(@date)
    @cycle_data = Array.new

    if @data.length > 0 && @data[0]['segments']
      segments = @data[0]['segments'].select { |s| s['type'] =='move' }

      segments.each do | s |
        s['activities'].each do | a |
          if a['group'] == 'cycling'
            r = BikeRide.new(DateTime.strptime(a['startTime'],"%Y%m%dT%H%M%S%z"), a['duration'].to_i * 1000, a['distance'] / 1000)
            @cycle_data.push r
          end
        end
      end

    end

    
    erb :summary_with_logging
  end

  get '/fitbit/summary/?' do
    redirect "fitbit/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end
  
  get '/fitbit/summary/:date' do
    
    user = User.find(session['user_id'])

    client = Fitgem::Client.new ({
      :consumer_key => ENV['FITBIT_CLIENT_ID'],
      :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
      :token => user.fitbit_account.access_token,
      :secret => user.fitbit_account.secret_token,
      :unit_system => Fitgem::ApiUnitSystem.METRIC
    })
   
    
    access_token = client.reconnect(user.fitbit_account.access_token, user.fitbit_account.secret_token)

    @data = client.activities_on_date @date
    @cycle_data = Array.new

    if @data['activities']
      @data['activities'].each do | a |
        if a['name'] == 'Bike'
          r = BikeRide.new(DateTime.strptime(a['startDate'] + ' ' + a['startTime'],"%Y-%m-%d %H:%M"), a['duration'], a['distance'])
          @cycle_data.push r 
        end
      end
    end

    
    
    erb :summary
  end

  post "/fitbit/log_activity" do
    client_secrets = JSON.parse(File.read(CLIENT_SECRETS_FILE))
    user = User.find(session['user_id'])

    client = Fitgem::Client.new ({
      :consumer_key => ENV['FITBIT_CLIENT_ID'],
      :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
      :token => user.fitbit_account.access_token,
      :secret => user.fitbit_account.secret_token,
      :unit_system => Fitgem::ApiUnitSystem.METRIC
    })
   
    access_token = client.reconnect(user.fitbit_account.access_token, user.fitbit_account.secret_token)

    # erb "
    #   <%=  params['activity_id'] %>
    #   <%=  params['duration'] %>
    #   <%=  params['distance'] %>
    #   <%=  params['start_time'] %>
    #   <%=  params['start_date'] %>", :layout => !request.xhr?
    
    @response = client.log_activity(
      :activityId => params[:activity_id],
      :durationMillis => params[:duration],
      :distance => params[:distance],
      :startTime => params[:start_time],
      :date => params[:start_date],
      :distanceUnit => Fitgem::ApiDistanceUnit.kilometers
    )

    if @response && @response['activityLog'] && @response['activityLog']['logId']
      erb "{response: '<%= @response['activityLog']['logId'] >%'", :layout => !request.xhr?
    else
      halt 404, "did not log"
    end

  end

end

__END__

@@layout
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="http://yui.yahooapis.com/pure/0.6.0/pure-min.css">
  <link rel="stylesheet" href="/css/side-menu.css">
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/2.1.4/jquery.min.js"></script>
</head>
<body>
  <div id="layout">
  <!-- Menu toggle -->
    <a href="#menu" id="menuLink" class="menu-link">
        <!-- Hamburger icon -->
        <span></span>
    </a>

    <div id="menu">
        <div class="pure-menu">
            <a class="pure-menu-heading" href="/">Sync</a>

            <ul class="pure-menu-list">
                <li class="pure-menu-item"><a href="/" class="pure-menu-link">Home</a></li>
                <li class="pure-menu-item"><a href="/select_user" class="pure-menu-link">Select User</a></li>
                <li class="pure-menu-item"><a href="/link_accounts" class="pure-menu-link">Link Accounts</a></li>
                <li class="pure-menu-item"><a href="/moves/summary" class="pure-menu-link">Moves Summary</a></li>
                <li class="pure-menu-item"><a href="/fitbit/summary" class="pure-menu-link">Fitbit Summary</a></li>
            </ul>
        </div>
    </div>
    <div id="main">

<%= yield %>
    </div>
  </div>
  <script src="/js/ui.js"></script>
</body>
</html>

@@index
<div class="header">
    <h1>Fitbit Moves Sync</h1>
    <h2>What's going on</h2>
</div>

<div class="content">
  <p>User name: <%=  @user.name  if @user%></p>
  <p>Fitbit UID: <%= @user.fitbit_account.uid if @user && @user.fitbit_account%></p>
  <p>Moves UID: <%= @user.moves_account.uid if @user && @user.moves_account%></p>
</div>

@@summary
<h1>Summary:</h1>
<p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
<h2>Rides:</h2>
<%= render_rides(@cycle_data) %>
<h2>Raw:</h2>
<pre><%= JSON.pretty_generate(@data)%></pre>

@@summary_with_logging
<h1>Summary:</h1>
<p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
<h2>Rides:</h2>
<%= render_rides_with_logging(@cycle_data) %>
<h2>Raw:</h2>
<pre><%= JSON.pretty_generate(@data)%></pre>

@@link_accounts
 <form action='/auth/moves' method='post'>
  <input type='submit' value='Link with Moves'/>
</form>
<form action='/auth/fitbit' method='post'>
  <input type='submit' value='Link with Fitbit'/>
</form>


