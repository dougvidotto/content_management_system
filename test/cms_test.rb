ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'fileutils'
require 'yaml'
require 'pry'

require_relative '../cms'

class CMSDTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    FileUtils.mkdir_p(data_path + '/history')
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm_rf(data_path + '/history')
  end

  def create_document(name, path, content = '')
    File.open(File.join(path, name), 'w') do |file|
      file.write(content)
    end
  end

  def session
    last_request.env['rack.session']
  end

  def admin_session
    { 'rack.session' => { username: 'admin' } }
  end

  def prepare_for_signup
    users = YAML.load_file(File.expand_path('../users.yml', __FILE__))
    users.delete('new_user')
    File.open(File.expand_path('../users.yml', __FILE__), 'w') { |file| file.write(users.to_yaml) }
  end

  def test_index
    create_document 'about.txt', data_path, ''
    create_document 'history.txt', data_path, ''
    create_document 'changes.txt', data_path, ''

    get '/'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.txt'
    assert_includes last_response.body, 'history.txt'
    assert_includes last_response.body, 'changes.txt'
  end

  def test_file_content
    content = 'This is a file having some text just for test'
    create_document 'changes.txt',  data_path, content

    get '/changes.txt'

    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']
    assert_includes last_response.body, content
  end

  def test_show_not_found_file_name
    create_document 'about.txt', data_path, ''
    create_document 'history.txt', data_path, ''
    create_document 'changes.txt', data_path, ''

    get '/which_file.txt'
    assert_equal 302, last_response.status
    assert_equal 'which_file.txt does not exist.', session[:alert]
  end

  def test_when_file_is_markdown
    markdown_content = '# This is markdown'

    create_document 'mardown_example.md', data_path, markdown_content

    get '/mardown_example.md'

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']

    assert_includes last_response.body, '<h1>This is markdown</h1>'
  end

  def test_edit_page
    create_document 'changes.txt', data_path, ''
    create_document 'hist.yml', data_path + '/history', ''

    get '/changes.txt/edit', {}, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']

    assert_includes last_response.body, 'Edit content of changes.txt:'
    assert_includes last_response.body, 'textarea'
  end

  def test_not_logged_user_accessing_edit_page
    get '/changes.txt/edit'

    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_post_changes_into_file
    create_document 'about.md', data_path, '# This is ruby..'
    create_document 'hist.yml', data_path + '/history', ''

    post '/about.md', { new_file_content: '# New headline' }, admin_session

    assert_equal 302, last_response.status

    hist_files = Dir.glob(data_path + '/history/about*.md')

    # Check if it was created an file with the same name as the original, but with a sufix of
    # current date and hour following the format: yyyy-mm-dd_hh-mm-ss
    assert_match(
      /about_\d{4}-\d{1,2}-\d{1,2}_\d{1,2}h-\d{1,2}m-\d{1,2}s.md/,
      hist_files.first
    )
    assert_equal 'about.md has been updated.', session[:alert]

    get '/about.md/edit', {}, admin_session

    assert_match(
      /about_\d{4}-\d{1,2}-\d{1,2}_\d{1,2}h-\d{1,2}m-\d{1,2}s.md/,
      last_response.body
     )

    assert_includes last_response.body, 'Saved by admin'

    get '/about.md'

    assert_equal 200, last_response.status
    assert_includes last_response.body, '<h1>New headline'
  end

  def test_accessing_historic_file_from_wrong_original_file
    create_document 'about.md', data_path, '# This is ruby..'
    create_document 'change.txt', data_path, 'Text example'
    create_document 'hist.yml', data_path + '/history', ''

    post '/about.md', { new_file_content: '# New headline' }, admin_session

    assert_equal 302, last_response.status

    hist_files = Dir.glob(data_path + '/history/about*.md')

    get "#{File.basename(hist_files.first)}/hist/change.txt/edit", {}, admin_session

    assert_equal 302, last_response.status
    assert_includes session[:alert], 'change.txt does not exist or is not linked to'
  end

  def test_post_changes_into_a_file_when_user_not_logged
    create_document 'about.md', data_path, '# This is ruby..'

    post '/about.md', new_file_content: '# New headline'

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_new_document_page
    get '/file/new', {}, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
  end

  def test_new_document_page_when_user_not_logged
    get '/file/new'

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_creating_new_document_with_a_name
    post '/file/new', { new_file: 'new_markdown.md' }, admin_session

    assert_equal 302, last_response.status
    assert_equal 'new_markdown.md was created.', session[:alert]

    post '/file/new', { new_file: 'new_text_file.txt' }, admin_session

    assert_equal 302, last_response.status
    assert_equal 'new_text_file.txt was created.', session[:alert]
  end

  def test_creating_new_file_with_empty_name
    post '/file/new', { new_file: '' }, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
    assert_includes last_response.body, 'A name is required.'

    post '/file/new', { new_file: '      ' }, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
    assert_includes last_response.body, 'A name is required.'
  end

  def test_creating_new_file_with_same_name
    create_document 'about.txt', data_path, ''
    post '/file/new', { new_file: 'about.txt' }, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
    assert_includes last_response.body, 'There is already a file named about.txt.'
  end

  def test_creating_new_file_without_extension
    post '/file/new', { new_file: 'test' }, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
    assert_includes last_response.body, 'The name must have a .txt or .md extension.'
  end

  def test_creating_file_with_wrong_extension
    post '/file/new', { new_file: 'test.bla' }, admin_session

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, "<input type='submit'"
    assert_includes last_response.body, 'Create'
    assert_includes last_response.body, "<form action='/file/new' method='post'"
    assert_includes last_response.body, 'The name must have a .txt or .md extension.'
  end

  def test_creating_file_when_user_not_logged
    post '/file/new', new_file: 'test.bla'
    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_delete_file
    create_document 'about.txt', data_path, ''
    create_document 'history.txt', data_path, ''
    create_document 'changes.txt', data_path, ''
    create_document 'file_to_be_deleted.txt', data_path, ''

    post '/file_to_be_deleted.txt/delete', {}, admin_session

    assert_equal 302, last_response.status
    assert_equal 'file_to_be_deleted.txt was deleted.', session[:alert]

    get last_response['Location']

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.txt'
    assert_includes last_response.body, 'history.txt'
    assert_includes last_response.body, 'changes.txt'
    refute_includes last_response.body, "<a href='/file_to_be_deleted.txt'>file_to_be_deleted.txt</a>"
    assert_includes last_response.body, 'file_to_be_deleted.txt was deleted.'
  end

  def test_delete_file_when_user_not_logged
    create_document 'about.txt', data_path, ''
    create_document 'history.txt', data_path, ''
    create_document 'changes.txt', data_path, ''
    create_document 'file_to_be_deleted.txt', data_path, ''

    post '/file_to_be_deleted.txt/delete'
    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_signin_page
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']

    assert_includes last_response.body, '<label>Username:'
    assert_includes last_response.body, '<label>Password:'
    assert_includes last_response.body, 'Sign In'
  end

  def test_successful_signing_in
    post '/users/signin', username: 'admin', password: 'secret'

    assert_equal 302, last_response.status
    assert_equal 'admin', session[:username]

    get last_response['Location']

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']

    assert_includes last_response.body, 'Welcome!'
    assert_includes last_response.body, 'Signed In as admin'
    assert_includes last_response.body, 'Sign Out'
  end

  def test_wrong_credentials_on_sign_in
    post '/users/signin', username: 'wrongname', password: 'wrongsecret'

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']

    assert_includes last_response.body, '<label>Username:'
    assert_includes last_response.body, '<label>Password:'
    assert_includes last_response.body, 'Sign In'
    assert_includes last_response.body, 'Invalid credentials'
    assert_includes last_response.body, 'wrongname'
    refute_includes last_response.body, 'wrongsecret'
  end

  def test_signing_out
    get '/', {}, admin_session

    post '/users/signout'

    assert_equal 302, last_response.status
    assert_nil session[:username]

    get last_response['Location']

    assert_includes last_response.body, 'You have been signed out.'
    assert_includes last_response.body, 'Sign In'
    assert_includes last_response.body, 'Sign Up'
  end

  def test_accessing_duplicate_file_page
    create_document 'history.txt', data_path, 'History file content'

    get '/history.txt/duplicate', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Duplicate content of history.txt:'
    assert_includes last_response.body, 'History file content'
  end

  def test_accessing_duplicate_page_when_user_not_logged
    create_document 'history.txt', data_path, 'History file content'

    get '/history.txt/duplicate'

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_accessing_duplicate_for_not_existing_file
    create_document 'history.txt', data_path, 'History file content'

    get '/tales.txt/duplicate', {}, admin_session

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'tales.txt does not exist.'
  end

  def test_duplicate_giving_same_file_name
    create_document 'history.txt', data_path, 'History file content'

    post '/history.txt/duplicate', { duplicated_file_name: 'history.txt' }, admin_session
    assert_equal 422, last_response.status

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'There is already a file named history.txt.'
    assert_includes last_response.body, 'Duplicate content of history.txt:'
    assert_includes last_response.body, 'History file content'
  end

  def test_duplicate_with_file_name_having_invalid_extension
    create_document 'history.txt', data_path, 'History file content'

    post '/history.txt/duplicate', { duplicated_file_name: 'history.bat' }, admin_session
    assert_equal 422, last_response.status

    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'The name must have a .txt or .md extension.'
    assert_includes last_response.body, 'Duplicate content of history.txt:'
    assert_includes last_response.body, 'History file content'
  end

  def test_succesful_file_duplicate
    create_document 'history.txt', data_path, 'History file content'
    dup_file_name = 'another_history.txt'
    dup_file_content = 'Another history file content'

    post '/history.txt/duplicate',
      { duplicated_file_name: dup_file_name,
        duplicated_file_content: dup_file_content },
        admin_session
    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'another_history.txt was created from history.txt'
    assert_includes last_response.body, "<a href='\/another_history.txt'>another_history.txt<\/a>"

    get '/another_history.txt'

    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']
    assert_includes last_response.body, dup_file_content
  end

  def test_signup_with_existent_username
    post '/users/signup', username: 'admin', password: 'secret'

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'admin is already registered in our system.'
  end

  def test_signup_with_blank_username_and_password
    post '/users/signup', username: '', password: ''

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Username and password must not be blank'

    post '/users/signup', username: 'someone', password: ''

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Username and password must not be blank'

    post '/users/signup', username: '', password: 'secret'

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Username and password must not be blank'
  end

  def test_signup_successfully
    prepare_for_signup

    post '/users/signup', username: 'new_user', password: 'my_password'

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_includes last_response.body, 'new_user registered successfully.'

    post '/users/signin', username: 'new_user', password: 'my_password'

    assert_equal 302, last_response.status
    assert_equal 'new_user', session[:username]

    get last_response['Location']

    assert_includes last_response.body, 'Signed In as new_user'
  end

  def test_accessing_image_upload_page
    get '/image/new', {}, admin_session

    assert_equal 200, last_response.status

    assert_includes(
      last_response.body,
      "<input type='file' name='image' accept='.jpg, .jpeg, .png, .gif'>"
    )
  end

  def test_accessing_image_upload_page_with_not_logged_user
    get '/image/new'
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_uploading_image_when_user_not_logged
    post '/image/new'
    assert_equal 302, last_response.status

    get last_response['Location']
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'You must be signed in to do that.'
  end

  def test_uploading_file_without_selecting_one
    post '/image/new', {}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'No file was selected to be uploaded.'
  end

  def test_uploading_file_that_is_not_an_image
    post '/image/new', { image: { filename: 'document.pdf' } }, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body,
     'File must have one of these extensions: .jpg, .jpeg, .png or .gif.'
  end

  def test_upload_file_successfully
    post('/image/new', { 'image' => Rack::Test::UploadedFile.new(image_path + '/document.jpg', 'image/jpeg') }, admin_session)

    assert_equal 302, last_response.status

    get last_response['Location']

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Upload of document.jpg was successfull'
  end
end
