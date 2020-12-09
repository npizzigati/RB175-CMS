require 'bundler/setup'
require 'sinatra'
require 'tilt/erubis'
require 'sinatra/reloader'
require 'sinatra/custom_logger'
require 'logger'
require 'redcarpet'
require 'json'
require 'bcrypt'

set :erb, escape_html: true
set :logger, Logger.new('log.txt')

ROOT = File.expand_path(__dir__).freeze
user_files_variable = test? ? 'tests/fakes/user_files'
                      : 'user_files'
data_variable = test? ? 'tests/fakes/data'
                      : 'data'
USER_FILES_PATH = File.join(ROOT, user_files_variable)
                      .freeze
DATA_PATH = File.join(ROOT, data_variable).freeze

# enable sessions
set :session_secret, 'secret'
enable :sessions

def initial_credentials
  [
    { 'username' => 'admin', 'password' => encrypt('secret')},
    { 'username' => 'frederik', 'password' => encrypt('fredspassword') }
  ]
end

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
  handle_unauthorized_user unless user_logged_in?
  file = params[:filename]
  path = pathify(file)
  @filename = file
  @file_content = File.read(path)
  erb :edit
end

def user_logged_in?(type = :regular)
  if type == :admin
    session[:username] == 'admin'
  else
    !session[:username].nil?
  end
end

def credentials_file_exists?
  File.exist? File.join(DATA_PATH, 'credentials.json')
end

def create_credentials_file
  path = File.join(DATA_PATH, 'credentials.json')
  File.open(path, 'w') do |f|
    f.write(initial_credentials.to_json)
  end
end

def parse_credentials
  path = File.join(DATA_PATH, 'credentials.json')
  JSON.parse File.read(path)
end

def handle_unauthorized_user(redirect_link = '/')
  session[:message] = 'Sorry, you are not' \
                      ' authorized to do that.'
  redirect redirect_link
end

get '/create/new-document' do
  handle_unauthorized_user unless user_logged_in?
  erb :new_document
end

post '/create/new-document' do
  handle_unauthorized_user unless user_logged_in?
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
  handle_unauthorized_user unless user_logged_in?
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
  user = retrieve_credentials(@username, password)

  if user
    session[:username] = @username
    session[:message] = "Welcome back, #{@username}."
    redirect '/'
  else
    session[:message] = 'Wrong username or password.'
    erb :sign_in
  end
end

def retrieve_all_credentials
  create_credentials_file unless credentials_file_exists?
  parse_credentials
end

def retrieve_credentials(username, password)
  user = retrieve_all_credentials.find do |usr|
    usr['username'] == username &&
      check(usr['password'], password)
  end
  user
end

post '/user/logout' do
  session[:username] = nil
  session[:message] = 'You have been signed out.'
  redirect '/'
end

get '/users/view' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  @all_credentials = retrieve_all_credentials
  erb :view_users
end

get '/users/edit/:username' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  @user = retrieve_user(params[:username])
  erb :edit_user
end

# Need to do some user validation here.
# Only admin should be able to see?
post '/users/edit' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  update_credentials_file(params, :edit)
  redirect '/users/view'
end

get '/users/add' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  erb :add_user
end

post '/users/add' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  update_credentials_file(params, :add)
  redirect '/users/view'
end

post '/users/delete/:username' do
  handle_unauthorized_user unless user_logged_in?(:admin)
  update_credentials_file(params, :delete)
  redirect '/users/view'
end

get '/*' do
  redirect '/'
end

def update_credentials_file(params, operation)
  all_credentials = retrieve_all_credentials

  new_username = params[:new_username]
  new_password = params[:new_password]

  case operation # This is for changes
  when :edit
    original_username = params[:original_username]
    user = all_credentials.find do |usr|
      usr['username'] == original_username
    end

    user['username'] = new_username
    user['password'] = encrypt(new_password)
  when :add
    new_user = { 'username' => new_username,
                 'password' => encrypt(new_password) }
    all_credentials << new_user
  when :delete
    user = all_credentials.find do |usr|
      usr['username'] == params[:username]
    end
    all_credentials.delete(user)
  end

  path = File.join(DATA_PATH, 'credentials.json')
  File.open(path, 'w') do |f|
    f.write(all_credentials.to_json)
  end
end

# Return string of password encrypted with bcrypt
def encrypt(password)
  BCrypt::Password.create(password).to_s
end

# Checks the entered_password against the stored password hash
def check(stored_hash, entered_password)
  BCrypt::Password.new(stored_hash) == entered_password
end

def my_logger(message)
  File.open(File.join(ROOT, 'log.txt'), 'a') do |f|
    f.write("\n" + Time.now.to_s + message)
  end
end

def retrieve_user(username)
  all_credentials = retrieve_all_credentials
  all_credentials.find do |usr|
    usr['username'] == username
  end
end

def valid?(filename)
  filename =~ /^[A-Za-z0-9_\-]+\.(md|txt)$/
end

def invalid_extension?(filename)
  !['.md', '.txt'].include?(File.extname(filename))
end
