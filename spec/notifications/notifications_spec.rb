ENV['RACK_ENV'] = 'test'
ENV['MOVES_CLIENT_SECRET'] = 'abc'
require File.expand_path('../../spec_helper', __FILE__)
require File.expand_path('../../../moves_notifications/moves_notifications', __FILE__)


def sign(body, timestamp, nonce) 
  Base64.encode64("#{OpenSSL::HMAC.digest('sha1',ENV['MOVES_CLIENT_SECRET'], [body, timestamp, nonce].join(''))}").chomp
end


describe 'Notifications' do
  include Rack::Test::Methods

  before do
    ResqueSpec.reset!
  end

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

  it "responds with a 403 error to a invalid signed message" do
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

  it "throws a 500 when there is non JSON junk sent in" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = 'bip bop boo'
    
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 500
  end

  it "throws a 500 when there is no userId in the JSON" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"missingId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T193103Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 500
  end

  it "throws a 500 when a date is malformed" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":123456789,"storylineUpdates":[{"reason":"DataUpload","startTime":"not_a_date","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 500
  end

  it "throws a 500 when a date is missing" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":123456789,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq 500
  end

  it "adds two items to a redis queue when a date range of two is passed in" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":38469648949403944,"storylineUpdates":[{"reason":"DataUpload","startTime":"20150704T140946Z","endTime":"20150705T193103Z","lastSegmentType":"place","lastSegmentStartTime":"20150705T145503Z"}]}'
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(ProcessDay).to have_queue_size_of(2)
    expect(ProcessDay).to have_queued('38469648949403944', Date.new(2015,7,4).to_s).in(:process_day)
    expect(ProcessDay).to have_queued('38469648949403944', Date.new(2015,7,5).to_s).in(:process_day)
  end

   it "can process multiple actions" do
    timestamp = '1436124689'
    nonce = '5juydMEgi7QLcl/QBO20UQ=='
    data = '{"userId":123456789,"storylineUpdates":[{"reason":"DataUpload","startTime":"20121212T072747Z","endTime":"20121212T093247Z","lastSegmentType":"place","lastSegmentStartTime":"20121212T082747Z"},{"reason":"ActivityUpdate","startTime":"20121213T072747Z","endTime":"20121213T073247Z"},{"reason":"PlaceUpdate","startTime":"20121214T082747Z","endTime":"20121214T093247Z"},{"reason":"PlaceRename","placeId":123456}]}'
    signature = sign(data, timestamp, nonce)

    header 'X-Moves-Signature', signature
    header 'X-Moves-Timestamp', timestamp
    header 'X-Moves-Nonce', nonce

    post '/', data, { "CONTENT_TYPE" => "application/json" }
    expect(ProcessDay).to have_queue_size_of(2)
    expect(ProcessDay).to have_queued('123456789', Date.new(2012,12,12).to_s).in(:process_day)
    expect(ProcessDay).to have_queued('123456789', Date.new(2012,12,13).to_s).in(:process_day)
  end



end
