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


CLIENT_SECRETS_FILE = 'client_secrets.json'
MOVES_AUTH_FILE = 'moves_auth.json'
FITBIT_AUTH_FILE = 'fitbit_auth.json'


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
  end




  configure do
    set :sessions, true
    set :inline_templates, true
    
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
      <p><a href='/moves_summary'>Todays activities</a></p>
    "
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
    client = Fitgem::Client.new(config[:oauth])
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(moves.daily_activities)}</pre>"
  end





client = Fitgem::Client.new(config[:oauth])

end

