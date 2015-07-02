require 'rubygems'
require 'bundler/setup'

require File.expand_path('../moves_app/moves_app', __FILE__)
require File.expand_path('../moves_notifications/moves_notifications', __FILE__)

use Rack::Static, :urls => ["/css", "/images", '/js'], :root => "public"

run Rack::URLMap.new(
	"/" => MovesApp.new, 
    "/notifications" => MovesNotifications.new
)
