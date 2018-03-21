require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'

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

def load_file(path)
  content = File.read(path)
  case File.extname(path)
  when '.md'
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(content)
  when '.txt'
    headers['Content-Type'] = 'text/plain;charset=utf-8'
    content
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
    load_file(file_path)
  else
    session[:message] = "#{file_name} does not exist."
    redirect '/'
  end
end
