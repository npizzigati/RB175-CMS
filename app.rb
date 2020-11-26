require 'sinatra'
require 'tilt/erubis'
require 'sinatra/development'

get '/' do
  erb :start
end
