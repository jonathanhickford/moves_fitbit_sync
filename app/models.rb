class User
  include Mongoid::Document
  include BCrypt

 
  field :name, type: String
  field :email, type: String
  field :password_hash, type: String
  
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
  attr_accessor :duration, :distance, :startDateTime

  def self.activityId
    @@activityId
  end

  def initialize(startDateTime = Time.now, duration, distance)
    @duration = duration
    @distance = distance
    @startDateTime = startDateTime
  end

  def startTime
    @startDateTime.strftime("%H:%M")
  end

  def date
    @startDateTime.strftime("%Y-%m-%d")
  end

end