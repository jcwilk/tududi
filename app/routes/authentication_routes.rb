class Sinatra::Application
  get '/login' do
    erb :login
  end

  post '/login' do
    @user = User.find_by(email: params[:email])
    if @user&.authenticate(params[:password])
      session[:user_id] = @user.id
      redirect '/'
    else
      logger.warn "Invalid credentials for user with email #{params[:email]}"
      @errors = ['Invalid credentials']
      erb :login
    end
  end

  get '/logout' do
    session.clear
    redirect '/login'
  end

  # New route added to handle registering new users
  post '/register' do
    @user = User.new(email: params[:email], password: params[:password])
    if @user.save
      status 200
      body ""
    else
      status 400
      body @user.errors.full_messages.join(', ')
    end
  end
end
