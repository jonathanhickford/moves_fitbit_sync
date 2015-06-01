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

CLIENT_SECRETS_FILE = 'client_secrets.json'


class User
  include Mongoid::Document
 
  field :name, type: String

  embeds_one :moves_account
  embeds_one :fitbit_account
end

class FitbitAccount
  include Mongoid::Document

  field :uid, type: String
  field :access_token, type: String
  field :secret_token, type: String

  embedded_in :user
end

class MovesAccount
  include Mongoid::Document

  field :uid, type: String
  field :access_token, type: String
  field :refresh_token, type: String
  field :expires_at, type: DateTime

  embedded_in :user
end



class MovesApp < Sinatra::Base
  
  configure do
    set :sessions, true
    set :inline_templates, true
    Mongoid.load!("./mongoid.yml")
    register Sinatra::Reloader
    
  end

  use OmniAuth::Builder do
    client_secrets = JSON.parse(File.read(CLIENT_SECRETS_FILE))
    provider :moves, client_secrets['moves_client_id'], client_secrets['moves_client_secret']
    provider :fitbit, client_secrets['fitbit_client_key'], client_secrets['fitbit_client_secret']
  end


  get '/' do
    redirect '/select_user' unless session['user_id']

    @user = User.find(session['user_id'])

    erb "
      <p>User name: <%=  @user.name  if @user%></p>
      <p>Fitbit UID: <%= @user.fitbit_account.uid if @user && @user.fitbit_account%></p>
      <p>Moves UID: <%= @user.moves_account.uid if @user && @user.moves_account%></p>
      <p><a href='/select_user'>Change user</a></p>
      <p><a href='/link_accounts'>Link Accounts</a></p>
      <p><a href='/moves_summary'>Todays moves activities</a></p>
      <p><a href='/fitbit_summary'>Todays fitbit activities</a></p>
    "
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
      "Error saving doc"
    end
  end



  get '/link_accounts' do
    erb "
     <form action='/auth/moves' method='post'>
        <input type='submit' value='Link with Moves'/>
      </form>
    <form action='/auth/fitbit' method='post'>
        <input type='submit' value='Link with Fitbit'/>
      </form>
    "
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

  
  get '/moves_summary' do
    redirect "moves_summary/#{Date.today.strftime('%Y-%m-%d')}"
  end

  get '/moves_summary/:date' do |date|
    begin
      puts date
      date = Date.strptime(date, '%Y-%m-%d')
    rescue  
      halt 404, "bad date"
    end

    user = User.find(session['user_id'])
    moves_token = user.moves_account.access_token
    moves = Moves::Client.new(moves_token)

    @moves_data = moves.daily_activities(date)
    @cycle_data = Array.new

    if @moves_data.length > 0 && @moves_data[0]['segments']
      segments = @moves_data[0]['segments'].select { |s| s['type'] =='move' }

      segments.each do | s |
        s['activities'].each do | a |
          @cycle_data.push a if a['group'] == 'cycling'
        end
      end

    end

    
    erb "
    <h1>Summary:</h1>
    <p><a href='/moves_summary/#{date - 1}'>Previous</a> - <a href='/moves_summary/#{date + 1}'>Next</a></p>
    <pre>#{JSON.pretty_generate(@cycle_data)}</pre>

    "
  end
  
  get '/fitbit_summary' do
    
    client_secrets = JSON.parse(File.read(CLIENT_SECRETS_FILE))
    user = User.find(session['user_id'])

    client = Fitgem::Client.new ({
      :consumer_key => client_secrets['fitbit_client_key'],
      :consumer_secret => client_secrets['fitbit_client_secret'],
      :token => user.fitbit_account.access_token,
      :secret => user.fitbit_account.secret_token
    })
   
    
    access_token = client.reconnect(user.fitbit_account.access_token, user.fitbit_account.secret_token)
    
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(client.activities_on_date 'today')}</pre>"
  end

end

