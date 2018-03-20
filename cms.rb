require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('test/data', __dir__)
  else
    File.expand_path('data', __dir__)
  end
end

get '/' do
  @files = Dir.entries(data_path).reject { |file| File.extname(file) == '' }
  erb :index, layout: :layout
end

get '/:file' do
  file_name = params[:file]
  file_path = data_path + "/#{file_name}"
  if File.exist?(file_path)
    status 200
    headers['Content-Type'] = 'text/plain;charset=utf-8'
    File.read(file_path)
  else
    session[:message] = "#{file_name} does not exist."
    redirect '/'
  end
end
