require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require "sinatra/reloader"
require 'sinatra/flash'
require 'omniauth'
require 'omniauth-moves'
require 'omniauth-fitbit'
require 'moves'
require 'fitgem'
require 'json'
require 'mongoid'
require 'warden'
require 'bcrypt'

FITBIT_BIKE_RIDE_PARENT_ID = 90001

require File.expand_path('../app/models', __FILE__)

class MovesApp < Sinatra::Base
  
  configure do
    set :sessions, true
    set :inline_templates, true
    Mongoid.load!("./mongoid.yml")
    register Sinatra::Flash
  end

  configure :development do
    register Sinatra::Reloader
    set :session_secret, "supersecret"
  end

  use OmniAuth::Builder do
    provider :moves, ENV['MOVES_CLIENT_ID'], ENV['MOVES_CLIENT_SECRET']
    provider :fitbit, ENV['FITBIT_CLIENT_ID'], ENV['FITBIT_CLIENT_SECRET']
  end

  use Warden::Manager do |config|
      # Tell Warden how to save our User info into a session.
      # Sessions can only take strings, not Ruby code, we'll store
      # the User's `id`
      config.serialize_into_session{|user| user.id }
      # Now tell Warden how to take what we've stored in the session
      # and get a User from that information.
      config.serialize_from_session{|id| User.find(id) }

      config.scope_defaults :default,
        # "strategies" is an array of named methods with which to
        # attempt authentication. We have to define this later.
        strategies: [:password],
        # The action is a route to send the user to when
        # warden.authenticate! returns a false answer. We'll show
        # this route below.
        action: '/unauthenticated'
      # When a user tries to log in and cannot, this specifies the
      # app to send the user to.
      config.failure_app = self
    end

    Warden::Manager.before_failure do |env,opts|
      env['REQUEST_METHOD'] = 'POST'
    end

    Warden::Strategies.add(:password) do
    def valid?
      params['user']['email'] && params['user']['password']
    end

    def authenticate!
      user = User.find_by(email: params['user']['email'])

      if user.nil?
        fail!('The email and password combination does not exist')
      elsif user.authenticate(params['user']['password'])
        success!(user, 'Successfully logged in')
      else
        fail!('The email and password combination does not exist')
      end
    end
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

    def authenticated!
      unless env['warden'].authenticated? 
       flash[:error] = "You need to login"
       redirect '/login' 
     end
      env['warden'].authenticate!
      @user = env['warden'].user
    end

    def login_logout_menu
      if env['warden'].authenticated?
        '<li class="pure-menu-item"><a href="/logout" class="pure-menu-link">Logout</a></li>'
      else 
        '<li class="pure-menu-item"><a href="/login" class="pure-menu-link">Login</a></li>'
      end
    end


  end

  get '/' do
    authenticated!
    
    erb :index
  end


  get '/register' do
    erb :register
  end

  post '/register' do
    user = User.new(params[:user])
    if user.save
      env['warden'].authenticate!
      redirect '/'
    else
      "Error saving user"
    end
  end

  get '/login' do
    erb :login
  end

  post '/login' do
    env['warden'].authenticate!
    flash[:success] = env['warden'].message
    redirect '/'
  end

  get '/logout' do
    env['warden'].raw_session.inspect
    env['warden'].logout
    flash[:success] = 'Successfully logged out'
    redirect '/login'
  end

  post '/unauthenticated' do
    session[:return_to] = env['warden.options'][:attempted_path]
    puts env['warden.options'][:attempted_path]
    flash[:error] = env['warden'].message || "You must log in"
    redirect '/login'
  end


  get '/link_accounts' do
    authenticated!
    erb :link_accounts
  end

  get '/auth/:provider/callback' do
    authenticated!
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
    authenticated!
    erb "<h1>Authentication Failed:</h1><h3>message:<h3><pre>#{params}</pre>"
  end


   before '*/summary/:date' do
    begin
      @date = Date.strptime(params['date'], '%Y-%m-%d')
    rescue  
      halt 404, "bad date"
    end
   end

   before '/moves/*' do
    authenticated!

    unless @user.moves_account && @user.moves_account.access_token
      flash[:warn] = "You need to link your moves account to the application"
      redirect '/link_accounts'
    end

    moves_token = @user.moves_account.access_token
    @moves = Moves::Client.new(moves_token)
   end

   before '/fitbit/*' do
    authenticated!

    unless @user.fitbit_account && @user.fitbit_account.access_token && @user.fitbit_account.secret_token
      flash[:warn] = "You need to link your fitbit account to the application"
      redirect '/link_accounts'
    end

    @client = Fitgem::Client.new ({
      :consumer_key => ENV['FITBIT_CLIENT_ID'],
      :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
      :token => @user.fitbit_account.access_token,
      :secret => @user.fitbit_account.secret_token,
      :unit_system => Fitgem::ApiUnitSystem.METRIC
    })
   
    @access_token = @client.reconnect(@user.fitbit_account.access_token, @user.fitbit_account.secret_token)
  end



  
  get '/moves/summary/?' do
    redirect "moves/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end

  get '/moves/summary/:date' do
    @data = @moves.daily_activities(@date)
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
    @data = @client.activities_on_date @date
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
    @response = @client.log_activity(
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
                <%= login_logout_menu %>
                <li class="pure-menu-item"><a href="/link_accounts" class="pure-menu-link">Link Accounts</a></li>
                <li class="pure-menu-item"><a href="/moves/summary" class="pure-menu-link">Moves Summary</a></li>
                <li class="pure-menu-item"><a href="/fitbit/summary" class="pure-menu-link">Fitbit Summary</a></li>
            </ul>
        </div>
    </div>
    <div id="main">
    <%= styled_flash %>
    <%= yield %>
    </div>
  </div>
  <script src="/js/ui.js"></script>
</body>
</html>

@@index
<div class="header">
    <h1>Fitbit Moves Sync</h1>
</div>

<div class="content">
  <p>User name: <%=  @user.name  if @user%></p>
  <p>Fitbit UID: <%= @user.fitbit_account.uid if @user && @user.fitbit_account%></p>
  <p>Moves UID: <%= @user.moves_account.uid if @user && @user.moves_account%></p>
</div>

@@summary
<div class="header">
  <h1>Summary</h1>
</div>
<div class="content">
  <p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
  <h2>Rides:</h2>
  <%= render_rides(@cycle_data) %>
  <h2>Raw:</h2>
  <pre><%= JSON.pretty_generate(@data)%></pre>
</div>

@@summary_with_logging
<div class="header">
  <h1>Summary</h1>
</div>
<div class="content">
  <p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
  <h2>Rides:</h2>
  <%= render_rides_with_logging(@cycle_data) %>
  <h2>Raw:</h2>
  <pre><%= JSON.pretty_generate(@data)%></pre>
</div>

@@link_accounts
<div class="header">
  <h1>Link Accounts</h1>
</div>
<div class="content">
   <form action='/auth/moves' method='post'>
    <input type='submit' value='Link with Moves'/>
  </form>
  <form action='/auth/fitbit' method='post'>
    <input type='submit' value='Link with Fitbit'/>
  </form>
</div>

@@register
<div class="header">
  <h1>Register</h1>
</div>
<div class="content">
  <form action='/register' method='POST'>
    <input type='hidden' name='_method' value='POST'/>
    Name: <input type='text' name ='user[name]'/>
    Email: <input type='text' name ='user[email]'/>
    Password: <input type='password' name ='user[password]'/>
    <input type='submit' name='submit' value='Save'/>
  </form>
</div>

@@login
<div class="header">
  <h1>Login</h1>
</div>
<div class="content">
  <form action='/login' method='POST'>
    <input type='hidden' name='_method' value='POST'/>
    Email: <input type='text' name ='user[email]'/>
    Password: <input type='password' name ='user[password]'/>
    <input type='submit' name='submit' value='Login'/>
  </form>
  <p><a href='/register'>Register a new account</a></p>
</div>


