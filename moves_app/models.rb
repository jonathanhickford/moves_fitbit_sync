class User
  include Mongoid::Document
  include BCrypt

 
  field :name, type: String
  field :email, type: String
  field :password_hash, type: String

  validates_presence_of :name, :email, message: 'Field is required'
  validates_uniqueness_of :email, :allow_blank => false
  validates_length_of :password, minimum: 8, too_short: 'Password must be at least 8 characters'
  validates_format_of :email, with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i, message: 'Email address must be valid'

  
  #attr_protected :password_hash
  attr_accessor :password
  

  embeds_one :moves_account
  embeds_one :fitbit_account

  before_save :encrypt_password

  def authenticate(attempted_password)
    user_pass = Password.new(self.password_hash)
    if user_pass == attempted_password
      true
    else
      false
    end
  end

  protected

  def encrypt_password
    self.password_hash = Password.create(@password)
  end

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

class BikeRide
  @@activityId = FITBIT_BIKE_RIDE_PARENT_ID
  attr_accessor :duration, :distance, :startDateTime, :source

  def self.activityId
    @@activityId
  end

  def initialize(startDateTime = Time.now, duration, distance, source)
    @duration = duration
    @distance = distance
    @startDateTime = startDateTime
    @source = source
  end

  def startTime
    @startDateTime.strftime("%H:%M")
  end

  def date
    @startDateTime.strftime("%Y-%m-%d")
  end

  def self.rides_from_fitbit(data)
    cycle_data = Hash.new
    if data['activities']
      data['activities'].each do | a |
        if a['name'] == 'Bike'
          r = BikeRide.new(DateTime.strptime(a['startDate'] + ' ' + a['startTime'],"%Y-%m-%d %H:%M"), a['duration'], a['distance'], :fitbit)
          cycle_data[r.startTime] = r 
        end
      end
    end
    cycle_data
  end

  def self.rides_from_moves(data)
    cycle_data = Hash.new
    if data.length > 0 && data[0]['segments']
      segments = data[0]['segments'].select { |s| s['type'] =='move' }
      segments.each do | s |
        s['activities'].each do | a |
          if a['group'] == 'cycling'
            r = BikeRide.new(DateTime.strptime(a['startTime'],"%Y%m%dT%H%M%S%z"), a['duration'].to_i * 1000, a['distance'] / 1000, :moves)
            cycle_data[r.startTime] = r 
          end
        end
      end
    end
    cycle_data
  end

  def self.merge_rides(fitbit_rides, moves_rides)
    fitbit_rides.merge(moves_rides) do | key, old_value, new_value |
      new_value.source = :both
      new_value
    end
  end

end