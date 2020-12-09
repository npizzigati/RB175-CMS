ENV['APP_ENV'] = 'test'

require 'bundler/setup'
require 'minitest/autorun'
require 'rack/test'
require 'logger'
require 'capybara/minitest'
require 'capybara/apparition'

require_relative '../app'

module TestHelpers
  def create_test_user_files
    # FileUtils.touch "#{USER_FILES_PATH}/herstory.txt"
    File.open("#{USER_FILES_PATH}/herstory.txt", 'w') do |f|
      f.write 'Kamala Harris is the first female vice president of the United States.'
    end
    # FileUtils.touch "#{USER_FILES_PATH}/sample_markdown.md"
    File.open("#{USER_FILES_PATH}/sample_markdown.md", 'w') do |f|
      f.write 'This is a sample paragragh.'
    end
  end

  def delete_test_user_files
    paths_to_delete = ["#{USER_FILES_PATH}/herstory.txt",
                       "#{USER_FILES_PATH}/sample_markdown.md",
                       "#{USER_FILES_PATH}/new_file.txt",
                       "#{DATA_PATH}/credentials.json"]

    paths_to_delete.each do |path|
      FileUtils.rm path if File.exist? path
    end
  end
end

class CapybaraTestCase < Minitest::Test
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  # Capybara.default_driver = :apparition

  def teardown
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end

class UnitAppTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelpers

  def app
    Sinatra::Application
  end

  def setup
    create_test_user_files
  end

  def teardown
    delete_test_user_files
    super
  end

  def session
    last_request.env['rack.session']
  end

  def admin_session
    session_hash = { username: 'admin',
                               password: 'secret' }
    { 'rack.session' => session_hash }
  end

  def setup_credentials_file(credentials_store)
    path = File.join(DATA_PATH, 'credentials.json')
    File.open(path, 'w') do |f|
      f.write(credentials_store.to_json)
    end
  end

  def test_filename_validator_catches_bad_extension
    filename = 'test.doc'
    actual = valid?(filename)
    assert_nil actual
  end

  def test_filename_validator_catches_bad_base_name
    filename = 'test<>.doc'
    actual = valid?(filename)
    assert_nil actual
  end

  def test_filename_validator_passes_good_name
    filename = 'test.txt'
    expected = true
    actual = valid?(filename)
    assert expected, actual
  end

  def test_extension_validator_catches_bad_extension
    filename = 'test.doc'
    expected = true
    actual = invalid_extension?(filename)
    assert_equal expected, actual
  end

  def test_extension_validator_passes_good_extension
    filename = 'file_1.md'
    expected = false
    actual = invalid_extension?(filename)
    assert_equal expected, actual
  end

  def test_start_returns_200_status
    get '/'
    assert_equal 200, last_response.status
  end

  def test_signing_in_creates_session_username
    post '/user/login', { username: 'admin',
                                   password: 'secret' }
    expected = 'admin'
    actual = session[:username]
    assert_equal expected, actual
  end

  def test_signing_out_removes_session_variables
    post '/user/logout'
    actual = session[:username]
    assert_nil actual
  end

  def test_can_set_session_variable_directly
    post '/', {}, admin_session
    expected = 'admin'
    actual = session[:username]
    assert_equal expected, actual
  end

  def test_user_logged_in_admin
    post '/', {}, admin_session
    expected = true
    actual = user_logged_in?(:admin)
    assert_equal expected, actual
  end

  def test_check_whether_credentials_file_exists_true
    path = File.join(DATA_PATH, 'credentials.json')
    FileUtils.touch path
    expected = true
    actual = credentials_file_exists?
    assert_equal expected, actual
  end

  def test_create_credentials_file
    create_credentials_file
    assert File.exist? File.join(DATA_PATH, 'credentials.json')
  end

  def test_parse_credentials
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    expected = credentials_store
    actual = parse_credentials
    assert_equal expected, actual
  end

  def test_retrieve_credentials_finds_user
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    expected = credentials_store.first
    actual = retrieve_credentials('admin', 'secret')
    assert_equal expected, actual
  end

  def test_retrieve_credentials_wrong_password
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    actual = retrieve_credentials('admin', 'wildguess')
    assert_nil actual
  end

  def test_retrieve_credentials_nonexistent_username
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    actual = retrieve_credentials('joe', 'joespassword')
    assert_nil actual
  end

  def test_user_edit_retrieves_user
    user = retrieve_user('admin')
    assert user['username'] = 'admin'
  end

  def test_update_credentials_file_change
    credentials_store = [{ 'username' => 'joe',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    params = {
      original_username: 'joe',
      new_username: 'joseph',
      new_password: 'secret'
    }
    update_credentials_file(params, :edit)
    user = retrieve_user('joseph')
    assert user['username'] = 'joseph'
  end

  def test_update_credentials_file_new
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    params = {
      new_username: 'roger',
      new_password: 'rogerspassword'
    }
    update_credentials_file(params, :add)
    expected = 2
    actual = retrieve_all_credentials.size
    assert_equal expected, actual
  end

  def test_password_encryption_functions
    password = 'secret'
    hash = encrypt(password)
    expected = true
    actual = check(hash, password)
    assert_equal expected, actual
  end

  def test_update_credentials_file_delete
    credentials_store = [{ 'username' => 'admin',
                           'password' => encrypt('secret') },
                         { 'username' => 'roger',
                           'password' => encrypt('secret') }]
    setup_credentials_file(credentials_store)
    params = { username: 'roger' }
    update_credentials_file(params, :delete)
    expected = 1
    actual = retrieve_all_credentials.size
    assert_equal expected, actual
  end
end

class IntegrationAppTest < CapybaraTestCase
  include TestHelpers

  Capybara.app = Sinatra::Application

  def setup
    create_test_user_files
  end

  def teardown
    delete_test_user_files
    super
  end

  def login_admin
    visit '/user/login'
    fill_in 'Username:', with: 'admin'
    fill_in 'Password:', with: 'secret'
    click_button 'Sign In'
  end


  def login_regular_user
    visit '/user/login'
    fill_in 'Username:', with: 'frederik'
    fill_in 'Password:', with: 'fredspassword'
    click_button 'Sign In'
  end

  def test_start_returns_status_200
    visit '/'
    assert page.status_code == 200
  end

  def test_start_returns_filename_list
    visit '/'
    assert_content(/herstory.txt.*markdown/)
  end

  def test_filename_route_returns_text_file
    visit '/herstory.txt'
    assert response_headers['Content-Type'].include? 'text/plain'
  end

  def test_file_does_not_exist_message
    visit '/nonexistentfile.txt'
    assert_content 'not found'
  end

  def test_file_does_not_exist_still_lists_files
    visit '/nonexistentfile.txt'
    assert_content 'herstory'
  end

  def test_file_renders_markdown_in_html
    visit '/sample_markdown.md'
    assert response_headers['Content-Type'].include? 'text/html'
  end

  def test_edit_link_shows_next_to_each_file_name
    visit '/'
    assert_content 'Edit'
  end

  def test_clicking_on_edit_link_takes_user_to_edit_page
    login_admin
    visit '/'
    first('li').click_link('Edit')
    assert_content 'Editing content of'
  end

  def test_edit_page_shows_document_in_text_area
    login_admin
    visit '/edit/herstory.txt'
    assert find('textarea').value =~ /Kamala/
  end

  def test_saving_edit_takes_user_to_home_page
    login_admin
    visit '/edit/herstory.txt'
    click_button('Save')
    assert_current_path '/'
  end

  def test_after_saving_edit_user_sees_message
    login_admin
    visit '/edit/herstory.txt'
    click_button('Save')
    assert_content 'updated'
  end

  def test_message_disappears_after_reloading_page
    login_admin
    visit '/edit/herstory.txt'
    click_button('Save')
    visit '/' # reload current path
    refute_content 'updated'
  end

  def test_edit_actually_edits_file
    login_admin
    visit '/edit/herstory.txt'
    find('textarea').fill_in(with: 'New Text.')
    click_button('Save')
    visit '/herstory.txt'
    assert_content 'New Text'
  end

  def test_new_document_link_appears_on_start_page
    visit '/'
    assert_content 'New Document'
  end

  def test_clicking_on_new_document_takes_user_to_create_document_page
    login_admin
    visit '/'
    find('a[href="/create/new-document"]').click
    assert_content 'Add a new document'
  end

  def test_successfully_creating_file_takes_user_back_to_filelist
    login_admin
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'herstory.txt'
  end

  def test_not_entering_file_name_when_creating_file_produces_advisory_message
    login_admin
    visit '/create/new-document'
    find('button').click
    assert_content 'Please enter a filename.'
  end

  def test_clicking_create_button_creates_new_file
    login_admin
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'new_file.txt'
  end

  def test_creating_new_file_produces_success_message
    login_admin
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'new_file.txt was created'
  end

  def test_entering_invalid_file_produces_error_message
    login_admin
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file>.txt')
    find('button').click
    assert_content 'Filename may only contain'
  end

  def test_delete_link_appears_in_initial_list
    visit '/'
    page.has_css?('li', text: 'Delete')
  end

  def test_clicking_delete_deletes_document
    login_admin
    visit '/'
    file = 'herstory.txt'
    find("a[href=\"/delete/#{file}\"]").click
    refute File.exist? pathify(file)
  end

  def test_clicking_delete_displays_message
    login_admin
    visit '/'
    file = 'herstory.txt'
    find("a[href=\"/delete/#{file}\"]").click
    message = "#{file} was deleted"
    assert_content message
  end

  def test_signed_out_user_sees_sign_in_page_at_start
    visit '/'
    page.assert_selector('button', text: 'Sign in')
  end

  def test_clicking_on_sign_in_button_takes_user_to_sign_in_form_page
    visit '/'
    find('button').click
    assert_content 'User Sign-In'
  end

  def test_sign_in_form_has_username_and_password_fields
    visit '/user/login'
    page.assert_selector('input[name="username"]')
    page.assert_selector('input[name="password"]')
  end

  def test_sign_in_form_has_submit_button_labeled_sign_in
    visit '/user/login'
    page.assert_selector('input[type="submit"]')
  end

  def test_signing_in_with_correct_credentials_redirects_to_start
    visit '/user/login'
    fill_in 'Username:', with: 'admin'
    fill_in 'Password:', with: 'secret'
    click_on 'Sign In'
    assert_content 'Welcome back, admin.'
  end

  def test_message_produced_by_invalid_credentials
    visit '/user/login'
    fill_in 'Username:', with: 'joe'
    fill_in 'Password:', with: 'pass'
    click_on 'Sign In'
    assert_content 'Wrong username or password.'
  end

  def test_username_entered_is_shown_on_form_on_subsequent_tries
    visit '/user/login'
    fill_in 'Username:', with: 'Joe'
    fill_in 'Password:', with: 'pass'
    click_on 'Sign In'
    assert_selector('input[value="Joe"]')
  end

  def test_signed_in_message_appears_on_start_page
    login_admin
    assert_content 'Signed in as admin'
  end

  def test_sign_out_button_appears_on_start_page
    login_admin
    assert_selector('button', text: 'Sign Out')
  end

  def test_clicking_sign_out_should_sign_out_user
    login_admin
    click_button 'Sign Out'
    assert_content 'File List'
    refute_content 'Signed in as admin'
  end

  def test_signing_out_produces_message
    login_admin
    click_button 'Sign Out'
    assert_content 'You have been signed out.'
  end

  def test_signed_out_user_redirected_to_start_when_clicks_on_edit
    visit '/'
    click_link 'Edit', match: :first
    assert_current_path '/'
  end

  def test_signed_out_user_unable_to_delete_file
    visit '/'
    click_link 'Delete', href: /herstory\.txt/
    assert File.exist? pathify('herstory.txt')
  end

  def test_unauthorized_edit_action_produces_message
    visit '/'
    click_link 'Edit', match: :first
    assert_content 'Sorry, you are not authorized to do that.'
  end

  def test_signed_out_user_unable_to_create_new_file
    visit '/'
    click_link 'New Document'
    assert_current_path '/'
    assert_content 'Sorry, you are not authorized to do that.'
  end

  def test_admin_user_sees_button_to_edit_users
    login_admin
    visit '/'
    assert_selector 'button', text: 'Edit Users'
  end

  def test_edit_users_button_does_not_appear_if_user_not_logged_in
    visit '/'
    refute_selector 'button', text: 'Edit Users'
  end

  def test_edit_users_button_does_not_appear_if_user_is_not_admin
    login_regular_user
    visit '/'
    refute_selector 'button', text: 'Edit Users'
  end

  def test_clicking_on_edit_users_button_takes_user_to_edit_users_page
    login_admin
    visit '/'
    click_button 'Edit Users'
    assert_content 'Users'
  end

  def test_view_users_shows_users
    login_admin
    click_button 'Edit Users'
    assert_content 'Username: admin'
  end

  def test_view_users_shows_edit_button
    login_admin
    click_button 'Edit Users'
    assert_selector 'button', text: 'Edit'
  end

  def test_clicking_on_edit_button_for_user_takes_you_to_user_edit_page
    login_admin
    click_button 'Edit Users'
    click_button 'Edit', match: :first
    assert_content 'Edit User'
  end

  def test_edit_user_page_displays_password_field
    login_admin
    click_button 'Edit Users'
    click_button 'Edit', match: :first
    assert_selector 'input[name="new_password"]'
  end

  # def test_edit_user_page_displays_username_field_for_users_except_admin
  #   login_admin
  #   click_button 'Edit Users'
  #   click_button 'Edit', match: :first
  #   assert_selector 'input[name="new_password"]'
  # end

  def test_view_users_page_displays_an_add_user_button
    login_admin
    click_button 'Edit Users'
    assert_selector 'button', text: 'Add User'
  end

  def test_clicking_on_add_user_button_should_take_admin_to_add_user_page
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    assert_content 'Add User'
  end

  def test_add_user_page_should_have_field_to_enter_username_and_password
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    assert_selector 'input[name="new_username"]'
    assert_selector 'input[name="new_password"]'
  end

  def test_added_user_appears_in_users_view
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    fill_in 'new_username', with: 'john'
    fill_in 'new_password', with: 'johnspassword'
    click_button 'Add User'
    assert_content 'Username: john'
  end

  def test_delete_button_appears_in_users_view
    login_admin
    click_button 'Edit Users'
    assert_selector 'button', text: 'Delete'
  end

  def test_delete_button_deletes_user
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    fill_in 'new_username', with: 'john'
    fill_in 'new_password', with: 'johnspassword'
    click_button 'Add User'
    assert_content 'Username: john'
    page.find('form[action="/users/delete/john"]').click_button 'Delete'
    refute_content 'Username: john'
  end

  def test_only_admin_can_see_users_page
    login_regular_user
    visit '/users/view'
    assert_current_path '/'
  end

  def test_there_is_no_delete_button_next_to_admin_user_in_users_view
    login_admin
    click_button 'Edit Users'
    refute_selector 'form[action="/users/delete/admin"]'
  end

  def test_password_is_not_stored_in_plaintext
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    fill_in 'new_username', with: 'john'
    fill_in 'new_password', with: 'johnspassword'
    click_button 'Add User'
    user = retrieve_user('john')
    assert user['password'] != 'johnspassword'
  end

  def test_password_is_stored_in_bcrypt_hash
    login_admin
    click_button 'Edit Users'
    click_button 'Add User'
    fill_in 'new_username', with: 'john'
    fill_in 'new_password', with: 'johnspassword'
    click_button 'Add User'
    user = retrieve_user('john')
    expected = true
    actual = BCrypt::Password.new(user['password']) == 'johnspassword'
    assert expected == actual
  end
end
