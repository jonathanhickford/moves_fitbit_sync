ENV['RACK_ENV'] = 'test'
ENV['MOVES_CLIENT_SECRET'] = 'abc'
require File.expand_path('../../spec_helper', __FILE__)
require File.expand_path('../../../moves_app/moves_app', __FILE__)




describe 'App' do
  include Rack::Test::Methods

  before do
    ResqueSpec.reset!
  end

  def app
    MovesApp
  end

  it "can select rides that are only in moves from a merged set of rides" do
    merged_rides = {
      '03:04' => BikeRide.new(DateTime.new(2015,1,2,3,4,0), '123', '456', :both),
      '07:09' => BikeRide.new(DateTime.new(2015,1,2,7,9,0), '234', '567', :moves),
      '07:08' => BikeRide.new(DateTime.new(2015,1,2,7,8,0), '234', '567', :fitbit)
    }
    expected_moves_ride = {
      '07:09' => BikeRide.new(DateTime.new(2015,1,2,7,9,0), '234', '567', :moves)
    }

    expect(BikeRide.select_moves_rides(merged_rides)).to eq expected_moves_ride
  end

  it "can merge a list of ride in moves and fitbit, marking them as present in both when they start at the same hour and minute" do 
    fitbit_rides = {
      '03:04' => BikeRide.new(DateTime.new(2015,1,2,3,4,10), '123', '456', :fitbit),
      '07:08' => BikeRide.new(DateTime.new(2015,1,2,7,8,0), '234', '567', :fitbit)
    }
    moves_rides = {
      '03:04' => BikeRide.new(DateTime.new(2015,1,2,3,4,10), '123', '456', :moves),
      '07:09' => BikeRide.new(DateTime.new(2015,1,2,7,9,0), '234', '567', :moves)
    }
    expected_merged_rides = {
      '03:04' => BikeRide.new(DateTime.new(2015,1,2,3,4,0), '123', '456', :both),
      '07:09' => BikeRide.new(DateTime.new(2015,1,2,7,9,0), '234', '567', :moves),
      '07:08' => BikeRide.new(DateTime.new(2015,1,2,7,8,0), '234', '567', :fitbit)
    }

    expect(BikeRide.merge_rides(fitbit_rides, moves_rides)).to eq expected_merged_rides
  end

  it "can select bike rides from moves data" do
    moves_data = JSON.parse '[{"date":"20150713","summary":[{"activity":"transport","group":"transport","duration":671.0,"distance":4180.0},{"activity":"walking","group":"walking","duration":734.0,"distance":628.0,"steps":1055,"calories":43},{"activity":"cycling","group":"cycling","duration":3466.0,"distance":19826.0,"calories":599}],"segments":[{"type":"move","startTime":"20150713T074222+0100","endTime":"20150713T075332+0100","activities":[{"activity":"transport","group":"transport","manual":false,"startTime":"20150713T074222+0100","endTime":"20150713T075333+0100","duration":671.0,"distance":4180.0}],"lastUpdate":"20150713T115203Z"},{"type":"place","startTime":"20150713T075332+0100","endTime":"20150713T080608+0100","activities":[{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T075505+0100","endTime":"20150713T075535+0100","duration":30.0,"distance":20.0,"steps":41,"calories":1},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T080006+0100","endTime":"20150713T080136+0100","duration":90.0,"distance":71.0,"steps":143,"calories":5}],"lastUpdate":"20150713T115203Z"},{"type":"move","startTime":"20150713T080608+0100","endTime":"20150713T082818+0100","activities":[{"activity":"cycling","group":"cycling","manual":false,"startTime":"20150713T080608+0100","endTime":"20150713T082817+0100","duration":1329.0,"distance":8013.0,"calories":241}],"lastUpdate":"20150713T115203Z"},{"type":"place","startTime":"20150713T082818+0100","endTime":"20150713T165027+0100","activities":[{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T082848+0100","endTime":"20150713T083049+0100","duration":121.0,"distance":154.0,"steps":206,"calories":11},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T105006+0100","endTime":"20150713T105036+0100","duration":30.0,"distance":41.0,"steps":82,"calories":3},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T115430+0100","endTime":"20150713T115510+0100","duration":40.0,"distance":28.0,"steps":56,"calories":2},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T120000+0100","endTime":"20150713T120148+0100","duration":108.0,"distance":86.0,"steps":171,"calories":6},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T135915+0100","endTime":"20150713T135933+0100","duration":18.0,"distance":9.0,"steps":11,"calories":1},{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T161748+0100","endTime":"20150713T162040+0100","duration":172.0,"distance":129.0,"steps":164,"calories":9}],"lastUpdate":"20150713T194448Z"},{"type":"move","startTime":"20150713T171824+0100","endTime":"20150713T173710+0100","activities":[{"activity":"cycling","group":"cycling","manual":false,"startTime":"20150713T171824+0100","endTime":"20150713T173710+0100","duration":1126.0,"distance":7864.0,"calories":235}],"lastUpdate":"20150713T194448Z"},{"type":"place","startTime":"20150713T173710+0100","endTime":"20150713T174830+0100","activities":[{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T173737+0100","endTime":"20150713T173837+0100","duration":60.0,"distance":46.0,"steps":92,"calories":3}],"lastUpdate":"20150713T194448Z"},{"type":"move","startTime":"20150713T174830+0100","endTime":"20150713T180521+0100","activities":[{"activity":"cycling","group":"cycling","manual":false,"startTime":"20150713T174830+0100","endTime":"20150713T180521+0100","duration":1011.0,"distance":3949.0,"calories":123}],"lastUpdate":"20150713T194448Z"},{"type":"place","startTime":"20150713T180521+0100","endTime":"20150713T204412+0100","activities":[{"activity":"walking","group":"walking","manual":false,"startTime":"20150713T195206+0100","endTime":"20150713T195311+0100","duration":65.0,"distance":44.0,"steps":89,"calories":3}],"lastUpdate":"20150713T194452Z"}],"caloriesIdle":1981,"lastUpdate":"20150713T194452Z"}]'

    expected_rides = {
      '08:06' => BikeRide.new(DateTime.new(2015, 7, 13, 8, 6), 1329000, 8.013, :moves),
      '17:18' => BikeRide.new(DateTime.new(2015, 7, 13, 17, 18), 1126000, 7.864, :moves),
      '17:48' => BikeRide.new(DateTime.new(2015, 7, 13, 17, 48), 1011000, 3.949, :moves)
    }
    expect(BikeRide.rides_from_moves(moves_data)).to eq expected_rides
  end

  it "can select bike rides from fitbit data" do
    fitbit_data = JSON.parse '{"activities":[{"activityId":1030,"activityParentId":90001,"activityParentName":"Bike","calories":248,"description":"Moderate - 12 to 13.9mph","distance":8.013,"duration":1329000,"hasStartTime":true,"isFavorite":false,"lastModified":"2015-07-13T19:59:54.476Z","logId":270662881,"name":"Bike","startDate":"2015-07-13","startTime":"08:06","steps":0},{"activityId":1040,"activityParentId":90001,"activityParentName":"Bike","calories":262,"description":"Fast - 14 to 15.9mph","distance":7.864,"duration":1126000,"hasStartTime":true,"isFavorite":false,"lastModified":"2015-07-13T19:59:57.069Z","logId":270615482,"name":"Bike","startDate":"2015-07-13","startTime":"17:18","steps":0},{"activityId":1010,"activityParentId":90001,"activityParentName":"Bike","calories":95,"description":"Very Leisurely - under 10 mph","distance":3.949,"duration":1011000,"hasStartTime":true,"isFavorite":false,"lastModified":"2015-07-13T19:59:59.377Z","logId":270624683,"name":"Bike","startDate":"2015-07-13","startTime":"17:48","steps":0}],"goals":{"activeMinutes":30,"caloriesOut":2184,"distance":8.05,"steps":9000},"summary":{"activeScore":-1,"activityCalories":1748,"caloriesBMR":1757,"caloriesOut":3132,"distances":[{"activity":"Bike","distance":8.013},{"activity":"Bike","distance":7.864},{"activity":"Bike","distance":3.949},{"activity":"total","distance":5.98},{"activity":"tracker","distance":5.98},{"activity":"loggedActivities","distance":19.826},{"activity":"veryActive","distance":0.57},{"activity":"moderatelyActive","distance":0.64},{"activity":"lightlyActive","distance":4.76},{"activity":"sedentaryActive","distance":0}],"fairlyActiveMinutes":28,"lightlyActiveMinutes":258,"marginalCalories":1001,"sedentaryMinutes":932,"steps":7269,"veryActiveMinutes":42}}'

    expected_rides = {
      '08:06' => BikeRide.new(DateTime.new(2015, 7, 13, 8, 6), 1329000, 8.013, :fitbit),
      '17:18' => BikeRide.new(DateTime.new(2015, 7, 13, 17, 18), 1126000, 7.864, :fitbit),
      '17:48' => BikeRide.new(DateTime.new(2015, 7, 13, 17, 48), 1011000, 3.949, :fitbit)
    }
    expect(BikeRide.rides_from_fitbit(fitbit_data)).to eq expected_rides
  end


end
