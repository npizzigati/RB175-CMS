ENV['APP_ENV'] = 'test'

require 'bundler/setup'
require 'minitest/autorun'
require 'rack/test'
require 'logger'
require 'capybara/minitest'
require 'capybara/apparition'
require 'pry'

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
    FileUtils.rm "#{USER_FILES_PATH}/herstory.txt"
    FileUtils.rm "#{USER_FILES_PATH}/sample_markdown.md"
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
    visit '/'
    first('li').click_link('Edit')
    assert_content 'Editing content of'
  end

  def test_edit_page_shows_document_in_text_area
    visit '/edit/herstory.txt'
    assert find('textarea').value =~ /Kamala/
  end

  def test_saving_edit_takes_user_to_home_page
    visit '/edit/herstory.txt'
    click_button('Save')
    assert_current_path '/'
  end

  def test_after_saving_edit_user_sees_message
    visit '/edit/herstory.txt'
    click_button('Save')
    assert_content 'updated'
  end

  def test_message_disappears_after_reloading_page
    visit '/edit/herstory.txt'
    click_button('Save')
    visit '/' # reload current path
    refute_content 'updated'
  end

  def test_edit_actually_edits_file
    FileUtils.cp('fakes/user_files/herstory.txt',
                 'fakes/user_files/herstory_tmp.txt')
    visit '/edit/herstory_tmp.txt'
    find('textarea').fill_in(with: 'New Text.')
    click_button('Save')
    visit '/herstory_tmp.txt'
    assert_content 'New Text'
  end

  def test_new_document_link_appears_on_start_page
    visit '/'
    assert_content 'New Document'
  end

  def test_clicking_on_new_document_takes_user_to_create_document_page
    visit '/'
    find('a[href="/create/new-document"]').click
    assert_content 'Add a new document'
  end

  def test_successfully_creating_file_takes_user_back_to_filelist
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'herstory.txt'
  end

  def test_not_entering_file_name_when_creating_file_produces_advisory_message
    visit '/create/new-document'
    find('button').click
    assert_content 'Please enter a filename.'
  end

  def test_clicking_create_button_creates_new_file
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'new_file.txt'
  end

  def test_creating_new_file_produces_success_message
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file.txt')
    find('button').click
    assert_content 'new_file.txt was created'
  end

  def test_entering_invalid_file_produces_error_message
    visit '/create/new-document'
    find('input').fill_in(with: 'new_file>.txt')
    find('button').click
    assert_content 'Filename may only contain'
  end
end
