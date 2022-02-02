
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions

# setup

clear_message_routes = ["/register"]

def db_connection(route)
    db = SQLite3::Database.new(route)
    db.results_as_hash = true
    return db
end

before do
    if session[:message] != nil && not(clear_message_routes.include?(request.path_info))
        p request.path_info
        p "hello"
        session[:message] = nil
    end
end

#get routes

get('/') do
    slim(:index)
end

get('/register') do
    slim(:register)
end

get('/login') do
    slim(:login)
end

get('/users/:id/profile') do
    slim(:"users/index")
end

#post routes

post('/users/new') do
    db = db_connection('db/db.db')
    username = params[:username]
    password = params[:password]
    ver_password = params[:ver_password]

    if password == ver_password
        salted_password = password + "salt"
        crypted_password = BCrypt::Password.create(salted_password)
        db.execute("INSERT INTO users(username,password,role) VALUES (?,?,?)",username,crypted_password,"guest")
    else
        session[:message] = "Register failed: password not equal to ver_password"
    end
    redirect('/register')
end