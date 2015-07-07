ENV['RACK_ENV'] = 'test'
ENV['MOVES_CLIENT_SECRET'] = 'abc'
require File.expand_path('../../spec_helper', __FILE__)
require File.expand_path('../../../moves_notifications/moves_notifications', __FILE__)
require 'rspec'
require 'json_spec'
require 'rack/test'

set :environment, :test


def sign(body, timestamp, nonce) 
  Base64.encode64("#{OpenSSL::HMAC.digest('sha1',ENV['MOVES_CLIENT_SECRET'], [body, timestamp, nonce].join(''))}").chomp
end


describe 'Notifications' do
  include Rack::Test::Methods
  include JsonSpec::Helpers

  def app
    MovesNotifications
  end

  it "responds with a 200 to a valid signed message" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T140946Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response).to be_ok
  end

   it "responds with an error to a invalid signed message" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T140946Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    
    signature = 'not_a_sig'

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 403
  end



end
