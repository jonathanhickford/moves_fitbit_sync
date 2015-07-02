require 'rubygems'
require 'bundler'

Bundler.require

FITBIT_BIKE_RIDE_PARENT_ID = ENV['FITBIT_BIKE_RIDE_PARENT_ID']

require File.expand_path('../models', __FILE__)

class MovesApp < Sinatra::Base
  
  configure do
    set :sessions, true
    set :inline_templates, true
    Mongoid.load!(File.expand_path('../../config/mongoid.yml', __FILE__))
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
              <th>Source</th>
              <% if @logging %><th>Log</th><% end %>
            </tr>
          </thead>
          <tbody>
            <% @rides.each_value do |ride| %>
              <tr>
                <td><%= ride.date %> </td>
                <td><%= ride.startTime %></td>
                <td><%= ride.duration %></td>
                <td><%= ride.distance %></td>
                <td><%= ride.source %></td>
                <% if @logging %>
                  <% if ride.source == :moves %>
                    <td><%= log_ride_to_fitbit_link(ride) %></td>
                  <% elsif ride.source == :fitbit %>
                    <td>N/A</td>
                  <% else %>
                    <td>Logged</td>
                  <% end %>
                <% end %>
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

    def fitbit_client
      unless @user.fitbit_account && @user.fitbit_account.access_token && @user.fitbit_account.secret_token
        flash[:warn] = "You need to link your fitbit account to the application"
        redirect '/'
      end

      fitbit = Fitgem::Client.new ({
        :consumer_key => ENV['FITBIT_CLIENT_ID'],
        :consumer_secret => ENV['FITBIT_CLIENT_SECRET'],
        :token => @user.fitbit_account.access_token,
        :secret => @user.fitbit_account.secret_token,
        :unit_system => Fitgem::ApiUnitSystem.METRIC
      })
     
      fitbit.reconnect(@user.fitbit_account.access_token, @user.fitbit_account.secret_token)
      fitbit
    end

    def moves_client
      unless @user.moves_account && @user.moves_account.access_token
        flash[:warn] = "You need to link your moves account to the application"
        redirect '/'
      end

      moves_token = @user.moves_account.access_token
      moves = Moves::Client.new(moves_token)
    end


  end

  get '/' do
    authenticated!
    
    haml :index
  end


  get '/register' do
    @user = User.new(params[:user])
    haml :register
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
      haml :register
    end
  end

  get '/login' do
    haml :login
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
    @moves = moves_client
   end

  before '/fitbit/*' do
    authenticated!
    @fitbit = fitbit_client
  end

  before '/moves_fitbit/*' do
    authenticated!
    @moves = moves_client
    @fitbit = fitbit_client
  end

  
  get '/moves/summary/?' do
    redirect "moves/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end

  get '/moves/summary/:date' do
    @data = @moves.daily_activities(@date)
    @cycle_data = BikeRide.rides_from_moves(@data)
    
    haml :summary_with_logging
  end

  get '/fitbit/summary/?' do
    redirect "fitbit/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end
  
  get '/fitbit/summary/:date' do
    @data = @fitbit.activities_on_date @date
    @cycle_data = BikeRide.rides_from_fitbit(@data)

    haml :summary
  end

  get '/moves_fitbit/summary/?' do
    redirect "moves_fitbit/summary/#{Date.today.strftime('%Y-%m-%d')}"
  end

  get '/moves_fitbit/summary/:date' do
    fitbit_data = @fitbit.activities_on_date @date
    fitbit_rides = BikeRide.rides_from_fitbit(fitbit_data)
    
    moves_data = @moves.daily_activities(@date)
    moves_rides = BikeRide.rides_from_moves(moves_data)
    
    @data = {:fitbit_data => fitbit_data, :moves_data => moves_data }
    @cycle_data = BikeRide.merge_rides(fitbit_rides, moves_rides)
    
    haml :summary_with_logging
  end




  post "/fitbit/log_activity" do
    @response = @fitbit.log_activity(
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






