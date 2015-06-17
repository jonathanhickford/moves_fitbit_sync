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
      config.serialize_into_session{|user| user.id }
      config.serialize_from_session{|id| User.find(id) }

      config.scope_defaults :default,
        strategies: [:password],
        action: '/unauthenticated'
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
    def render_rides(rides, logging=false)
      @rides = rides
      @logging = logging
      if @rides.length > 0
        erb "
        <table class='pure-table pure-table-bordered'>
          <thead>
            <tr>
              <th>Date</th>
              <th>Start Time</th>
              <th>Duration (ms)</th>
              <th>Distance (km)</th>
              <% if @logging %><th>Log</th><% end %>
            </tr>
          </thead>
          <tbody>
            <% @rides.each do |ride| %>
              <tr>
                <td><%= ride.date %> </td>
                <td><%= ride.startTime %></td>
                <td><%= ride.duration %></td>
                <td><%= ride.distance %></td>
                <% if @logging %><td><%= log_ride_to_fitbit_link(ride) %></td><% end %>
              </tr>
            <% end %>
          </tbody>
        </table>     
        "
      else
        erb "<p>No rides logged</p>"
      end
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
    @user = User.new(params[:user])
    erb :register
  end

  post '/register' do
    @user = User.new(params[:user])
    if @user.save
      env['warden'].authenticate!
      flash[:success] = 'Welcome. You are logged in'
      redirect '/'
    else
      error_message = ""
      p @user.errors.messages
      @user.errors.messages.each do |field, messages|
        error_message << "<ul>"
        error_message << "<li>#{field.capitalize}:<ul>"
        messages.each {|message| error_message << "<li>#{message}</li>"}
        error_message << "</ul></li>"
        error_message << "</ul>"
      end
      flash.now[:error] = error_message
      erb :register
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
      redirect '/'
    end

    moves_token = @user.moves_account.access_token
    @moves = Moves::Client.new(moves_token)
   end

   before '/fitbit/*' do
    authenticated!

    unless @user.fitbit_account && @user.fitbit_account.access_token && @user.fitbit_account.secret_token
      flash[:warn] = "You need to link your fitbit account to the application"
      redirect '/'
    end

    @fitbit = Fitgem::Client.new ({
      :consumer_key => ENV['FITBIT_CLIENT_ID'],
      :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
      :token => @user.fitbit_account.access_token,
      :secret => @user.fitbit_account.secret_token,
      :unit_system => Fitgem::ApiUnitSystem.METRIC
    })
   
    @access_token = @fitbit.reconnect(@user.fitbit_account.access_token, @user.fitbit_account.secret_token)
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
    @data = @fitbit.activities_on_date @date
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
            <a class="pure-menu-heading" href="/">Fitbit Sync</a>

            <ul class="pure-menu-list">
                <li class="pure-menu-item"><a href="/" class="pure-menu-link">Home</a></li>
                <%= login_logout_menu %>
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
  <p>User name: <%=  @user.name %></p>
  
  <% if @user.fitbit_account%>
    <p>You have successfully linked your fitbit account to the application</p>
    <p>Fitbit UID: <%= @user.fitbit_account.uid %></p>
  <% else %>
    <p>You haven't linked your moves account to the application</p>
    <form action='/auth/moves' method='post'>
      <input type='submit' value='Link with Moves'/>
    </form>
  <% end %>

  <% if @user.moves_account%>
    <p>You have successfully linked your moves account to the application</p>
    <p>Moves UID: <%= @user.moves_account.uid %></p>
  <% else %>
    <p>You haven't linked your fitbit account to the application</p>
    <form action='/auth/fitbit' method='post'>
      <input type='submit' value='Link with Fitbit'/>
    </form>
  <% end %>
  
</div>

@@summary
<div class="header">
  <h1>Summary</h1>
</div>
<div class="content">
  <p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
  <h2>Rides:</h2>
  <%= render_rides(@cycle_data, false) %>
  <% if params['debug'] %>
    <h2>Raw:</h2>
    <pre><%= JSON.pretty_generate(@data)%></pre>
  <% end %>
</div>

@@summary_with_logging
<div class="header">
  <h1>Summary</h1>
</div>
<div class="content">
  <p><a href='<%= @date - 1 %>'>Previous</a> - <a href='<%= @date + 1%>'>Next</a> - <a href='.'>Today</a></p>
  <h2>Rides:</h2>
  <%= render_rides(@cycle_data, true) %>
  <% if params['debug'] %>
    <h2>Raw:</h2>
    <pre><%= JSON.pretty_generate(@data)%></pre>
  <% end %>
</div>


@@register
<div class="header">
  <h1>Register</h1>
</div>
<div class="content pure-g">
  <form class="pure-form pure-u-1" action='/register' method='POST' >
    <fieldset class="pure-group">
      <input type='hidden' name='_method' value='POST'/>
      <input type='text' class="pure-u-1" name ='user[name]' value = '<%= @user.name %>' placeholder ='Name'/>
      <input type='text' class="pure-u-1" name ='user[email]' value = '<%= @user.email %>' placeholder='Email'/>
      <input type='password' class="pure-u-1" name ='user[password]' placeholder='Password'/>
    </fieldset>
    <input type='submit' name='submit' value='Register' class='pure-u-1 pure-button pure-button-primary'/>

  </form>
</div>

@@login
<div class="header">
  <h1>Login</h1>
</div>
<div class="content pure-g">
  <form class="pure-form pure-u-1" action='/login' method='POST'>
    <fieldset class="pure-group">
      <input type='hidden' name='_method' value='POST'/>
      <input type='text' class="pure-u-1" name ='user[email]' placeholder='Email'/>
      <input type='password' class="pure-u-1" name ='user[password]' placeholder='Password'/>
      <input type='submit' name='submit' value='Login' class='pure-u-1 pure-button pure-button-primary'/>
      </fieldset>
  </form>
  <p class="pure-form pure-u-1" ><a href='/register'>Register a new account</a></p>
</div>


