require 'sinatra'
require 'sinatra/activerecord'
require 'securerandom'
require 'byebug'

require './app/models/user'
require './app/models/area'
require './app/models/project'
require './app/models/task'
require './app/models/tag'
require './app/models/note'

require './app/helpers/authentication_helper'
require './app/helpers/task_helper'

require './app/routes/authentication_routes'
require './app/routes/tasks_routes'
require './app/routes/projects_routes'
require './app/routes/areas_routes'
require './app/routes/notes_routes'

helpers AuthenticationHelper

use Rack::MethodOverride

set :database_file, './app/config/database.yml'
set :views, proc { File.join(root, 'app/views') }
set :public_folder, 'public'

configure do
  enable :sessions
  set :sessions, httponly: true, secure: (production? && ENV['TUDUDI_INTERNAL_SSL_ENABLED'] == 'true'),
                 expire_after: 2_592_000
  set :session_secret, ENV.fetch('TUDUDI_SESSION_SECRET') { SecureRandom.hex(64) }

  # Auto-create user if not exists
  if ENV['TUDUDI_USER_EMAIL'] && ENV['TUDUDI_USER_PASSWORD'] && ActiveRecord::Base.connection.table_exists?('users')
    user = User.find_or_initialize_by(email: ENV['TUDUDI_USER_EMAIL'])
    if user.new_record?
      user.password = ENV['TUDUDI_USER_PASSWORD']
      user.save
    end
  end
end

use Rack::Protection

before do
  require_login
end

helpers TaskHelper

helpers do
  def current_path
    request.path_info
  end

  def partial(page, options = {})
    erb page, options.merge!(layout: false)
  end

  def nav_link_active?(path, query_params = {}, project_id = nil)
    current_uri = request.path_info
    current_query = request.query_string
    current_params = Rack::Utils.parse_nested_query(current_query)
    is_project_page = current_uri.include?('/project/') && path.include?('/project/')

    if is_project_page
      current_uri == path && (!project_id || current_uri.end_with?("/#{project_id}"))
    elsif !query_params.empty?
      current_uri == path && query_params.all? { |k, v| current_params[k] == v }
    else
      current_uri == path && current_params.empty?
    end
  end

  def nav_link(path, query_params = {}, project_id = nil)
    is_active = nav_link_active?(path, query_params, project_id)

    classes = 'nav-link py-1 px-3'
    classes += ' active-link' if is_active

    classes
  end

  def update_query_params(key, value)
    uri = URI(request.url)
    params = Rack::Utils.parse_nested_query(uri.query)
    params[key] = value # Update or add the key-value pair
    Rack::Utils.build_query(params)
  end

  def url_without_tag
    uri = URI(request.url)
    params = Rack::Utils.parse_nested_query(uri.query)
    params.delete('tag') # Remove the 'tag' parameter
    uri.query = Rack::Utils.build_query(params)
    uri.to_s
  end
end

get '/' do
  redirect '/tasks?due_date=today'
end

get '/inbox' do
  @tasks = current_user.tasks
                       .incomplete
                       .left_joins(:tags)
                       .where(project_id: nil, due_date: nil)
                       .where(tags: { id: nil }) # Filter tasks with no tags
                       .order('tasks.created_at DESC')

  erb :inbox
end
