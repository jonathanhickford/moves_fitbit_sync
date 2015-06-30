ENV['RACK_ENV'] = 'test'

require File.expand_path('../../../moves_notifications/moves_notifications', __FILE__)
require 'rspec'
require 'json_spec'
require 'rack/test'

set :environment, :test

describe 'Notifications' do
  include Rack::Test::Methods
  include JsonSpec::Helpers

  def app
    MovesNotifications
  end

  it "responds with a 200" do
    header 'X-Moves-Signature', 'xMbCdVO044lZCHiwEDBty+ae1oA='
    header 'X-Moves-Timestamp', '1390571569'
    header 'X-Moves-Nonce', 'abcdefghijklmnopqrstuvwxyz'
    post '/', "{ 'j': 's', 'o': 'n' }", { "CONTENT_TYPE" => "application/json" }
    expect(last_response).to be_ok
    #expect(last_response.body).to eq('Hello World')
  end



end