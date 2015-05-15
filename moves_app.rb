require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'omniauth'

require 'omniauth'
require 'omniauth-moves'
require 'omniauth-fitbit'
require 'moves'
require 'fitgem'
require 'json'

require 'mongoid'

CLIENT_SECRETS_FILE = 'client_secrets.json'
MOVES_AUTH_FILE = 'moves_auth.json'
FITBIT_AUTH_FILE = 'fitbit_auth.json'


class User
  include Mongoid::Document
 
  field :name, type: String

  has_one :moves_account
  has_one :fitbit_account
end

class FitbitAccount
  include Mongoid::Document

  field :uid, type: String
  field :access_token, type: String
  field :secret_token, type: String

  belongs_to :user
end

class MovesAccount
  include Mongoid::Document

  field :uid, type: String
  field :access_token, type: String
  field :refresh_token, type: String
  field :expires_at, type: DateTime

  belongs_to :user
end



class MovesApp < Sinatra::Base
  
  helpers do
    def load_moves_access_token_from_file
      begin
        if File.file?(MOVES_AUTH_FILE)
          auth = JSON.parse(File.read(MOVES_AUTH_FILE))
          auth['credentials']['token']
        else
          nil
        end
      rescue
        nil
      end
    end

    def load_fitbit_access_token_from_file
      begin
        if File.file?(FITBIT_AUTH_FILE)
          auth = JSON.parse(File.read(FITBIT_AUTH_FILE))
          [auth['credentials']['token'] , auth['credentials']['secret']]
        else
          [nil, nil]
        end
      rescue
        [nil, nil]
      end
    end



  end




  configure do
    set :sessions, true
    set :inline_templates, true
    Mongoid.load!("./mongoid.yml")
    
  end

  use OmniAuth::Builder do
    client_secrets = JSON.parse(File.read(CLIENT_SECRETS_FILE))
    provider :moves, client_secrets['moves_client_id'], client_secrets['moves_client_secret']
    provider :fitbit, client_secrets['fitbit_client_key'], client_secrets['fitbit_client_secret']
  end


  get '/' do
    session['moves_access_token'] = load_moves_access_token_from_file()
    erb "
      <p><%= session['moves_access_token'] %></p>
      <p><a href='/grant_access'>Grant Access to Accounts</a></p>
      <p><a href='/moves_summary'>Todays moves activities</a></p>
      <p><a href='/fitbit_summary'>Todays fitbit activities</a></p>
    "
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





  get '/grant_access' do
    erb "
     <form action='/auth/moves' method='post'>
        <input type='submit' value='Sign in with Moves'/>
      </form>
    <form action='/auth/fitbit' method='post'>
        <input type='submit' value='Sign in with Fitbit'/>
      </form>
    "
  end

  get '/auth/:provider/callback' do
    json = JSON.pretty_generate(request.env['omniauth.auth'])
    
    if params[:provider] == "moves"
      File.open(MOVES_AUTH_FILE, 'w') { |file| file.write(json) }
      session['moves_access_token'] = load_moves_access_token_from_file()
    elsif params[:provider] == "fitbit"
      File.open(FITBIT_AUTH_FILE, 'w') { |file| file.write(json) }
    end

    erb "<h1>#{params[:provider]}</h1>
         <pre>#{json}</pre>"
  end
  
  get '/auth/failure' do
    erb "<h1>Authentication Failed:</h1><h3>message:<h3><pre>#{params}</pre>"
  end

  get '/moves_summary' do
    moves = Moves::Client.new(session['moves_access_token'])
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(moves.daily_activities)}</pre>"
  end
  
  get '/fitbit_summary' do
    
    client_secrets = JSON.parse(File.read(CLIENT_SECRETS_FILE))
    credentials = load_fitbit_access_token_from_file()

    client = Fitgem::Client.new ({
      :consumer_key => client_secrets['fitbit_client_key'],
      :consumer_secret => client_secrets['fitbit_client_secret'],
      :token => credentials[0],
      :secret =>credentials[1]
    })
   
    
    access_token = client.reconnect(credentials[0],credentials[1])
    
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(client.activities_on_date 'today')}</pre>"
  end


end

