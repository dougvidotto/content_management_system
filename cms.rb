require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, escape_html: true
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('test/data', __dir__)
  else
    File.expand_path('data', __dir__)
  end
end

def image_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('test/images', __dir__)
  else
    File.expand_path('public/images', __dir__)
  end
end

def file_path(name, additional = '')
  File.join(data_path + '/' + additional, File.basename(name))
end

def load_file(path)
  case File.extname(path)
  when '.md'
    headers['Content-Type'] = 'text/html;charset=utf-8'
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(File.read(path))
  when '.txt'
    headers['Content-Type'] = 'text/plain'
    File.read(path)
  end
end

def load_user_credentials
  credential_path =
    if ENV['RACK_ENV'] == 'test'
      File.expand_path('test/users.yml', __dir__)
    else
      File.expand_path('users.yml', __dir__)
    end
  users = YAML.load_file(credential_path)
  return {} unless users
  users
end

def save_users_credentials(users)
  credential_path =
    if ENV['RACK_ENV'] == 'test'
      File.expand_path('test/users.yml', __dir__)
    else
      File.expand_path('users.yml', __dir__)
    end

  File.open(credential_path, 'w+') { |file| file.write(users.to_yaml) }
end

def valid_credentials?(username, password)
  users = load_user_credentials
  users.any? do |name, pass|
    name == username && BCrypt::Password.new(pass) == password
  end
end

def user_not_logged_warning
  (session[:alert] = 'You must be signed in to do that.') & (redirect '/')
end

def verify_user_logged
  user_not_logged_warning unless session[:username]
end

def check_file(name)
  if name.empty?
    session[:alert] = 'A name is required.'
  elsif !name.match(/.+(\.txt|\.md)/)
    session[:alert] = 'The name must have a .txt or .md extension.'
  elsif File.exist?(File.join(data_path, File.basename(name)))
    session[:alert] = "There is already a file named #{name}."
  end
end

def check_user(users, new_name, new_password)
  if users.keys.include? new_name
    session[:alert] = "#{new_name} is already registered in our system."
  elsif new_name.empty? || new_password.empty?
    session[:alert] = 'Username and password must not be blank'
  end
end

def check_image(image)
  if !image
    session[:alert] = 'No file was selected to be uploaded.'
  elsif !image[:filename].match(/.+(\.png|\.jpg|\.jpeg|\.gif)/)
    session[:alert] =
      'File must have one of these extensions: .jpg, .jpeg, .png or .gif.'
  end
end

def create_file_name_with_date_and_hour_sufix(name)
  now = Time.now
  file_name_without_extension = File.basename(name, File.extname(name))
  time_format =
    "#{now.year}-#{now.month}-#{now.day}_#{now.hour}h-#{now.min}m-#{now.sec}s"

  file_extension = File.extname(name)
  file_path(file_name_without_extension + '_' +
              time_format + file_extension, 'history')
end

get '/' do
  @files = Dir.entries(data_path).reject { |file| File.extname(file) == '' }
  erb :index, layout: :layout
end

get '/:file' do
  name = params[:file]
  if File.exist?(file_path(name))
    load_file(file_path(name))
  else
    session[:alert] = "#{name} does not exist."
    redirect '/'
  end
end

get '/file/new' do
  verify_user_logged
  erb :new_document, layout: :layout
end

post '/file/new' do
  verify_user_logged
  name = params[:new_file].strip
  session[:alert] = check_file(name)

  if session[:alert]
    erb :new_document, layout: :layout
  else
    File.new(file_path(name), 'w+')
    session[:alert] = "#{name} was created."
    redirect '/'
  end
end

get '/:file/edit' do
  name = params[:file]
  verify_user_logged
  if File.exist?(file_path(name))
    @content = File.read(file_path(name))
    files = YAML.load_file(file_path('hist.yml', 'history'))
    files ||= {}

    @history_files = files.select { |current_file, _| current_file == name }
    erb :edit, layout: :layout
  else
    session[:alert] = "#{name} does not exist."
    redirect '/'
  end
end

post '/:file' do
  verify_user_logged
  file_content = params[:new_file_content]
  name = params[:file]
  files = YAML.load_file(file_path('hist.yml', 'history'))
  files ||= {}

  hist_file_path = create_file_name_with_date_and_hour_sufix(name)

  File.open(hist_file_path, 'w+') do |file|
    file.write(File.read(file_path(name)))
  end

  if files[name].nil?
    files[name] = [{ File.basename(hist_file_path) => session[:username] }]
  else
    files[name] << { File.basename(hist_file_path) => session[:username] }
  end

  File.open(file_path('hist.yml', 'history'), 'w+') do |file|
    file.write(files.to_yaml)
  end

  File.open(file_path(name), 'w') { |file| file << file_content }
  session[:alert] = "#{name} has been updated."
  redirect '/'
end

get '/:hist_file/hist/:file/edit' do
  hist_name = params[:hist_file]
  current_name = params[:file]
  verify_user_logged

  if File.exist?(data_path + '/history/' + hist_name)
    @content = File.read(data_path + '/history/' + hist_name)
    files = YAML.load_file(file_path('hist.yml', 'history'))

    @history_files = files.select do |file, _|
      file == current_name && files[file].any? do |saved_files|
        saved_files.key?(hist_name)
      end
    end

    if @history_files.empty?
      session[:alert] =
        "#{current_name} does not exist or is not linked to #{hist_name}"
      redirect '/'
    end

    erb :edit, layout: :layout
  else
    session[:alert] = "#{hist_name} does not exist."
    redirect '/'
  end
end

post '/:file/delete' do
  verify_user_logged
  name = params[:file]

  files = YAML.load_file(file_path('hist.yml', 'history'))
  files ||= {}

  history_files = files.select { |file, _| file == name }

  # Delete all associated historic files
  history_files.each_value do |saved_files|
    saved_files.each do |hist_files|
      File.delete(file_path(hist_files.keys.first, 'history'))
    end
  end

  # Save to yaml only those that were not deleted
  remaining = files.reject do |file, _|
    file == name
  end

  File.open(file_path('hist.yml', 'history'), 'w+') do |file|
    file.write(remaining.to_yaml)
  end

  File.delete(file_path(name))
  session[:alert] = "#{name} was deleted."
  redirect '/'
end

get '/users/signin' do
  erb :signin, layout: :layout
end

post '/users/signin' do
  username = params[:username]
  password = params[:password]
  if !valid_credentials?(username, password)
    session[:alert] = 'Invalid credentials'
    erb :signin, layout: :layout
  else
    session[:alert] = 'Welcome!'
    session[:username] = username
    redirect '/'
  end
end

post '/users/signout' do
  session[:username] = nil
  session[:alert] = 'You have been signed out.'
  redirect '/'
end

# View the sign up page
get '/users/signup' do
  erb :signup, layout: :layout
end

# Register a user into users.yml file
post '/users/signup' do
  existent_users = load_user_credentials
  new_name = params[:username].strip
  new_password = params[:password].strip
  session[:alert] = check_user(existent_users, new_name, new_password)
  if session[:alert]
    status 422
    erb :signup, layout: :layout
  else
    existent_users[new_name] = BCrypt::Password.create(new_password).to_s
    save_users_credentials(existent_users)
    session[:alert] = "#{new_name} registered successfully."
    redirect '/'
  end
end

# View the duplicate file page
get '/:file/duplicate' do
  verify_user_logged
  name = params[:file]
  if File.exist?(file_path(name))
    @content = File.read(file_path(name))
    erb :duplicate, layout: :layout
  else
    session[:alert] = "#{name} does not exist."
    redirect '/'
  end
end

# Create a file from another file
post '/:file/duplicate' do
  verify_user_logged
  duplicated_name = params[:duplicated_file_name]
  current_name = params[:file]
  session[:alert] = check_file(duplicated_name)
  if session[:alert]
    @content = File.read(file_path(current_name))
    status 422
    erb :duplicate, layout: :layout
  else
    File.open(file_path(duplicated_name), 'w') do |file|
      file.write(params[:duplicated_file_content])
    end
    session[:alert] = "#{duplicated_name} was created from #{current_name}."
    redirect '/'
  end
end

get '/image/new' do
  verify_user_logged
  erb :images, layout: :layout
end

post '/image/new' do
  verify_user_logged
  session[:alert] = check_image(params[:image])
  if session[:alert]
    status 422
    erb :images, layout: :layout
  else
    filename = params[:image][:filename]
    file_content = params[:image][:tempfile]

    File.open(File.join(image_path, File.basename(filename)), 'w+') do |file|
      file.write(file_content.read)
    end

    session[:alert] = "Upload of #{filename} was successfull"
    redirect '/'
  end
end
