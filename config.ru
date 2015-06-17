require 'rubygems'
require 'bundler/setup'

require File.expand_path('../app/moves_app', __FILE__)

use Rack::Static, :urls => ["/css", "/images", '/js'], :root => "public"
run MovesApp.new

