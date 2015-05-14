require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'omniauth'

require 'omniauth'
require 'omniauth-moves'
require 'moves'
require 'json'


MOVES_CLIENT_SECRETS_FILE = 'moves_client_secrets.json'
MOVES_AUTH_FILE = 'moves_auth.json'



class MovesApp < Sinatra::Base
  configure do
    set :sessions, true
    set :inline_templates, true
    set :access_token, nil
    if File.file?('auth.json')
      auth = JSON.parse(File.read(MOVES_AUTH_FILE))
      p auth['credentials']['token']
      set :access_token, auth['credentials']['token']
    end


  end

  use OmniAuth::Builder do
    moves_client_secrets = JSON.parse(File.read(MOVES_CLIENT_SECRETS_FILE))
    provider :moves, moves_client_secrets['client_id'], client_secrets['client_secret']
  end


  get '/' do
    erb "
      <p><%= settings.access_token %></p>
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
    auth = JSON.parse(File.read(MOVES_AUTH_FILE))
    set :access_token, auth['credentials']['token']

    erb "<h1>#{params[:provider]}</h1>
         <pre>#{json}</pre>"
  end
  
  get '/auth/failure' do
    erb "<h1>Authentication Failed:</h1><h3>message:<h3><pre>#{params}</pre>"
  end

  get '/summary' do
    moves = Moves::Client.new(settings.access_token)
    
    erb "<h1>Summary:</h1><pre>#{JSON.pretty_generate(moves.daily_activities)}</pre>"
  end
  
end

