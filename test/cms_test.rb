ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'fileutils'

require_relative '../cms'

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    FileUtils.mkdir_p(data_path+"/history")
  end
  
  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm_rf(data_path+"/history")
  end
  
  def create_document(name, content = "", path)
    File.open(File.join(path, name), "w") do |file|
      file.write(content)
    end
  end

  def test_index
    create_document "about.txt", "", data_path
    create_document "history.txt", "", data_path
    create_document "changes.txt", "", data_path
    
    get '/'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['Content-Type']
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "history.txt"
    assert_includes last_response.body, "changes.txt"
  end
end
