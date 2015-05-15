require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'omniauth'

require 'omniauth'
require 'omniauth-moves'
require 'moves'
require 'json'


CLIENT_SECRETS_FILE = 'client_secrets.json'
MOVES_AUTH_FILE = 'moves_auth.json'



class MovesApp < Sinatra::Base
  
  helpers do
    def load_access_token_from_file
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
  end


  get '/' do
    session['access_token'] = load_access_token_from_file()
    erb "
      <p><%= session['access_token'] %></p>
      <p><a href='/grant_access'>Grant Access to Moves Account</a></p>
      <p><a href='/summary'>Todays activities</a></p>
    "
  end


  get '/grant_access' do
    erb "
     <form action='/auth/moves' method='post'>
        <input type='submit' value='Sign in with Moves'/>
      </form>
    "
  end

  get '/auth/:provider/callback' do
    json = JSON.pretty_generate(request.env['omniauth.auth'])
    File.open(MOVES_AUTH_FILE, 'w') { |file| file.write(json) }
    session['access_token'] = load_access_token_from_file()

    erb "<h1>#{params[:provider]}</h1>
         <pre>#{json}</pre>"
  end
  
  get '/auth/failure' do
    erb "<h1>Authentication Failed:</h1><h3>message:<h3><pre>#{params}</pre>"
  end

  get '/summary' do
    moves = Moves::Client.new(session['access_token'])
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(moves.daily_activities)}</pre>"
  end
  
end

