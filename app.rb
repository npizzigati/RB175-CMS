require 'bundler/setup'
require 'sinatra'
require 'tilt/erubis'
require 'sinatra/reloader'

set :erb, :escape_html => true

USER_FILES_DIRECTORY = 'user_files'.freeze

helpers do
end

def user_files_path(file = nil)
  root = File.expand_path(__dir__)
  path = File.join(root, USER_FILES_DIRECTORY)
  path = File.join(path, file) if file
  path
end

def retrieve_filenames
  files = []
  Dir.open(user_files_path) do |entry|
    files << entry if Dir.exist? entry
  end
end

get '/' do
  @filenames = retrieve_filenames
  erb :start
end

get '/:filename' do
  content_type 'text/plain'
  File.read(user_files_path(params[:filename]))
end
