require 'sinatra'
require 'sinatra/reloader'

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
