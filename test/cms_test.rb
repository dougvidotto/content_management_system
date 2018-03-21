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

  def test_viewing_text_files
    create_document 'history.txt', '2015 - Ruby 2.3 released.', data_path
    get '/history.txt'

    assert_equal 200, last_response.status
    assert_equal "text/plain;charset=utf-8", last_response['Content-Type']
    assert_includes last_response.body, '2015 - Ruby 2.3 released.'
  end

  def test_viewing_non_existing_files
    create_document 'history.txt', '2015 - Ruby 2.3 released.', data_path
    get '/changes.txt'
    assert_equal 302, last_response.status

    get last_response['Location']
    
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['Content-Type']
    assert_includes last_response.body, 'changes.txt does not exist'
  end

  def test_viewing_markdown_file
    markdown_content = "# This is an example of a file that contains Markdown code!"
    create_document "mardown_example.md", markdown_content, data_path

    get '/mardown_example.md'

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h1>This is an example of a file that contains Markdown code!</h1>'
  end
end
