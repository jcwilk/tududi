module Sinatra
  class Application
    def update_task_tags(task, tags_json)
      return if tags_json.blank?

      begin
        tag_names = JSON.parse(tags_json).map { |tag| tag['value'] }.uniq
        tags = tag_names.map do |name|
          current_user.tags.find_or_create_by(name: name)
        end
        task.tags = tags
      rescue JSON::ParserError
        puts "Failed to parse JSON for tags: #{tags_json}"
      end
    end

    get '/tasks' do
      @tasks = current_user.tasks.includes(:project, :tags)

      case params[:due_date]
      when 'today'
        today = Date.today
        @tasks = @tasks.incomplete.where('due_date <= ?', today.end_of_day)
      when 'upcoming'
        one_week_from_today = Date.today + 7.days
        @tasks = @tasks.incomplete.where(due_date: Date.today..one_week_from_today)
      when 'never'
        @tasks = @tasks.incomplete.where(due_date: nil)
      else
        @tasks = params[:status] == 'completed' ? @tasks.complete : @tasks.incomplete
      end

      if params[:order_by]
        order_column, order_direction = params[:order_by].split(':')
        order_direction ||= 'asc'
        @tasks = @tasks.order("tasks.#{order_column} #{order_direction}")
      end

      # Filter by tag if tag parameter is present
      if params[:tag]
        tag = params[:tag]
        @tasks = @tasks.joins(:tags).where(tags: { name: tag })
      end

      @tasks = @tasks.to_a.uniq

      erb :'tasks/index'
    end

    post '/task/create' do
      task_attributes = {
        name: params[:name],
        priority: params[:priority],
        due_date: params[:due_date],
        user_id: current_user.id
      }

      if params[:project_id].blank?
        task = current_user.tasks.build(task_attributes)
      else
        project = current_user.projects.find_by(id: params[:project_id])
        halt 400, 'Invalid project.' unless project
        task = project.tasks.build(task_attributes)
      end

      if task.save
        update_task_tags(task, params[:tags])
        redirect request.referrer || '/'
      else
        halt 400, 'There was a problem creating the task.'
      end
    end

    patch '/task/:id' do
      task = current_user.tasks.find_by(id: params[:id])

      halt 404, 'Task not found.' unless task

      task_attributes = {
        name: params[:name],
        priority: params[:priority],
        due_date: params[:due_date]
      }

      if params[:project_id] && !params[:project_id].empty?
        project = current_user.projects.find_by(id: params[:project_id])
        halt 400, 'Invalid project.' unless project
        task.project = project
      else
        task.project = nil
      end

      if task.update(task_attributes)
        update_task_tags(task, params[:tags])
        redirect request.referrer || '/'
      else
        halt 400, 'There was a problem updating the task.'
      end
    end

    patch '/task/:id/toggle_completion' do
      content_type :json
      task = current_user.tasks.find_by(id: params[:id])
      if task
        task.completed = !task.completed
        if task.save
          task.to_json
        else
          status 422
          { error: 'Unable to update task' }.to_json
        end
      else
        status 400
        { error: 'Task not found' }.to_json
      end
    end

    delete '/task/:id' do
      task = current_user.tasks.find_by(id: params[:id])
      halt 404, 'Task not found.' unless task

      if task.destroy
        redirect request.referrer || '/'
      else
        halt 400, 'There was a problem deleting the task.'
      end
    end
  end
end
