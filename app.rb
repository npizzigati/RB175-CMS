require 'bundler/setup'
require 'sinatra'
require 'tilt/erubis'
require 'sinatra/reloader'
require 'sinatra/custom_logger'
require 'logger'
require 'redcarpet'
require 'json'

set :erb, escape_html: true
set :logger, Logger.new('log.txt')

ROOT = File.expand_path(__dir__).freeze
variable_part = test? ? 'tests/fakes/user_files'
                      : 'user_files'
USER_FILES_PATH = File.join(ROOT, variable_part)
                      .freeze

# enable sessions
set :session_secret, 'secret'
enable :sessions

def pathify(file)
  File.join(USER_FILES_PATH, file)
end

def convert_to_markdown(text)
  target = Redcarpet::Render::HTML
  markdown = Redcarpet::Markdown.new(target)
  markdown.render(text)
end

def retrieve_filenames(path)
  entries = Dir.open(path)
  entries.reject do |entry|
    Dir.exist? entry
  end
end

get '/' do
  @filenames = retrieve_filenames(USER_FILES_PATH)
  erb :start
end

get '/:filename' do
  file = params[:filename]
  path = pathify(file)
  unless File.exist? path
    session[:message] = "\"#{file}\" not found."
    redirect '/'
  end

  if File.extname(file) == '.md'
    content_type 'text/html'
    convert_to_markdown(File.read(path))
  else
    content_type 'text/plain'
    File.read(path)
  end
end

post '/:filename' do
  file = params[:filename]
  path = pathify(file)
  edited_content = params[:edited_content]
  File.open(path, 'w') do |f|
    f.write(edited_content)
  end
  session[:message] = "#{file} has been updated."
  redirect '/'
end

get '/edit/:filename' do
  validate_user
  file = params[:filename]
  path = pathify(file)
  @filename = file
  @file_content = File.read(path)
  erb :edit
end

def user_logged_in?
  session[:username]
end

def validate_user
  unless user_logged_in?
    session[:message] = 'You must be signed' \
                        ' in to do that.'
    redirect '/'
  end
end

get '/create/new-document' do
  validate_user
  erb :new_document
end

post '/create/new-document' do
  filename = params[:filename]
  if valid?(filename)
    logger.info 'filename valid'
    FileUtils.touch pathify(filename)
    session[:message] = "#{filename} was created."
    redirect '/'
  end
  message = if filename == ''
              'Please enter a filename.'
            elsif invalid_extension?(filename)
              'Filename extension must be ".md"' \
              ' or ".txt".'
            else
              'Filename may only contain' \
              ' letters, numbers, underscores' \
              ' and periods.'
            end
  session[:message] = message
  redirect '/create/new-document'
end

get '/delete/:filename' do
  validate_user
  file = params[:filename]
  logger.info "Going to delete #{file}"
  FileUtils.rm pathify(file)
  session['message'] = "#{file} was deleted."
  redirect '/'
end

get '/user/login' do
  erb :sign_in
end

post '/user/login' do
  @username = params[:username]
  password = params[:password]
  if [@username, password] == %w[admin secret]
    session[:username] = @username
    session[:message] = "Welcome back, #{@username}."
    redirect '/'
  else
    session[:message] = 'Wrong username or password.'
    erb :sign_in
  end
end

post '/user/logout' do
  session[:username] = nil
  session[:message] = 'You have been signed out.'
  redirect '/'
end

def valid?(filename)
  filename =~ /^[A-Za-z0-9_\-]+\.(md|txt)$/
end

def invalid_extension?(filename)
  !['.md', '.txt'].include?(File.extname(filename))
end
