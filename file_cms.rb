require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

# cms.rb
def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def local_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test", __FILE__)
  else
    File.expand_path("..", __FILE__)
  end
end

root = File.expand_path("..", __FILE__)

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def file_exists?(file)
  Dir.entries("data").include?(file)
end

def load_file_content(file_path, file_type)
  content = File.read(file_path)
  case file_type
    #when 'txt'#
    #  headers['Content-Type'] = 'text/plain'
    #  File.read(file_path)
    #when 'md'
    #  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    #  markdown.render(File.read(file_path))
    when 'md'
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
      markdown.render(content)
    else
      headers['Content-Type'] = 'text/plain'
      content
  end
end

get "/view" do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file_content(file_path, "rb")
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

def signed_in?
  session.key?(:username)
end

def require_sign_in
  unless signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

class PasswordDigester
  def self.encrypt(password)
    BCrypt::Password.create(password)
  end

  def self.check?(password, encrypted_password)
    BCrypt::Password.new(encrypted_password) == password
  end
end

def valid_user?(user, password)
  credentials = YAML.load_file(File.join(local_path, 'users.yaml'))

  if credentials.key?(user)
    PasswordDigester.check?(password, credentials[user])
  else
    false
  end
end


get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end
  erb :files, layout: :layout
end


get "/new" do
  require_sign_in
  erb :new
end

post "/create" do
  require_sign_in

  filename = params[:filename].to_s

  if filename.size == 0
    session[:message] = "A name is required"
    status 422
    erb :new
  else
    file_path = File.join(data_path, filename)
    File.write(file_path, "")
    session[:message] = "#{params[:filename]} was created."
    redirect "/"
  end
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  if valid_user?(params[:username], params[:password])
    session[:username] = params[:username]
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/:file_name" do
  file_path = File.join(data_path, params[:file_name])
  file_name = params[:file_name]
  file_type = file_name.split('.')[1]
  #file_path = root + '/data/' + file_name
  if file_exists?(file_name)
    load_file_content(file_path, file_type)
  else
    session[:message] = "#{file_name} does not exist"
    redirect "/"
  end
end


get "/:file_name/edit" do
  require_sign_in

  file_path = File.join(data_path, params[:file_name])
  @file_name = params[:file_name]
  @file_type = @file_name.split('.')[1]
  if file_exists?(@file_name)
    @file_content = File.read(file_path)
    erb :edit, layout: :layout
  else
    session[:message] = "#{@file_name} does not exist"
    redirect "/"
  end
end

post "/:file_name/delete" do
  require_sign_in

  file_path = File.join(data_path, params[:file_name])
  @file_name = params[:file_name]
  @file_type = @file_name.split('.')[1]
  if file_exists?(@file_name)
    File.delete(file_path)
    session[:message] = "#{@file_name} has been deleted."
    redirect "/"
  else
    session[:message] = "#{@file_name} does not exist."
    redirect "/"
  end
end


post "/:file_name" do
  require_sign_in

  file_path = File.join(data_path, params[:file_name])
  @file_name = params[:file_name]
  @file_type = @file_name.split('.')[1]
  if file_exists?(@file_name)
    File.open(file_path, 'w') {|file| file.write(params[:new_text])}
    session[:message] = "#{@file_name} has been updated."
  else
    session[:message] = "#{@file_name} does not exist"
  end
  redirect "/"
end