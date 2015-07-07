ENV['RACK_ENV'] = 'test'
require File.expand_path('../../spec_helper', __FILE__)
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

  it "responds with a 200 to a valid signed message" do
    header 'X-Moves-Signature', '2TrS4GUm/2ylXq03hXhTeZQ7oNQ='
    header 'X-Moves-Timestamp', '1436124689'
    header 'X-Moves-Nonce', '5juydMEgi7QLcl/QBO20UQ=='

    message = '{"userId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T140946Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    post '/', message, { "CONTENT_TYPE" => "application/json" }
    expect(last_response).to be_ok
  end

   it "responds with an error to a invalid signed message" do
    header 'X-Moves-Signature', 'not_a_real_sig'
    header 'X-Moves-Timestamp', '1436124689'
    header 'X-Moves-Nonce', '5juydMEgi7QLcl/QBO20UQ=='

    message = '{"userId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T140946Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    post '/', message, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 403
  end



end
