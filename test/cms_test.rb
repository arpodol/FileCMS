ENV["RACK_ENV"] = "test"

require "fileutils"

require "minitest/autorun"
require "rack/test"


require_relative "../file_cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    create_login
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end


  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def create_login
    File.open(File.join(local_path, 'users.yaml'), "w") do |file|
      file.write('{
                   admin: $2a$12$cSLuHQ0TA556ozblaI7GtewhA.vKxHxw/V8Y7U8r4uQPg25vp/2Pq
                 }'
      )
    end
  end


  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes  last_response.body, 'about.md'
    assert_includes  last_response.body, 'changes.txt'
  end

  def test_history
    history_text = "1993 - Yukihiro Matsumoto dreams up Ruby.
            1995 - Ruby 0.95 released.
            1996 - Ruby 1.0 released.
            1998 - Ruby 1.2 released.
            1999 - Ruby 1.4 released.
            2000 - Ruby 1.6 released.
            2003 - Ruby 1.8 released.
            2007 - Ruby 1.9 released.
            2013 - Ruby 2.0 released.
            2013 - Ruby 2.1 released.
            2014 - Ruby 2.2 released.
            2015 - Ruby 2.3 released."

    create_document "history.txt",history_text

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "2014 - Ruby 2.2 released."
  end

  def test_about
    markdown_text = "# Ruby is...

A dynamic, open source programming language with a focus on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write."

    create_document "about.md", markdown_text

    get "/about.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_nonexistent
    get "/notafile.ext"
    assert_equal 302, last_response.status
    assert_equal "notafile.ext does not exist", session[:message]
  end

  def test_editing_doc
    create_document "changes.txt"

    get "/changes.txt/edit", {}, admin_session
    assert_equal 200, last_response.status

    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_editing_doc_signed_out
    create_document "changes.txt"

    get "/changes.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_update_doc
    create_document "changes.txt"
    post "/changes.txt", {new_text: "test words"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test words"
  end

  def test_update_doc_signed_out
    create_document "changes.txt"
    post "/changes.txt", {new_text: "test words"}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_creating_doc
    post "/create", {filename: "new.md"}, admin_session
    assert_equal 302, last_response.status

    assert_equal "new.md was created.", session[:message]

    get "/"
    assert_includes last_response.body, "new.md"
  end

  def test_creating_doc_signed_out
    post "/create", filename: "new.md"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_empty_file_name
    post "/create", {filename: ""}, admin_session
    assert_includes last_response.body, "A name is required"
    assert_equal 422, last_response.status
  end

  def test_create_empty_file_name_signed_out
    post "/create", filename: ""
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_delete_file
    create_document "changes.txt"

    post "/changes.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_delete_file_signed_out
    create_document "changes.txt"

    post "/changes.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_signin
    get "/"
    assert_includes last_response.body, "Sign In"

    get "/users/signin"
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"
  end

  def test_invalid_login
    post "/users/signin", username: "user", password: "12345"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_valid_login
    post "/users/signin", username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin."
  end

  def test_signout
    get "/", {}, {"rack.session" => { username: "admin" } }
    assert_includes last_response.body, "Signed in as admin"
    post "/users/signout"
    refute_includes last_response.body, "Signed in"
    assert_equal "You have been signed out.", session[:message]
    assert_nil session[:username]
    get "/"
    assert_includes last_response.body, "Sign In"
  end
end