
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions

# setup

clear_message_routes = ["/register", "/error"]

def db_connection(route)
    db = SQLite3::Database.new(route)
    db.results_as_hash = true
    return db
end

before do
    if session[:message] != nil && not(clear_message_routes.include?(request.path_info))
        session[:message] = nil
    end
end

#get routes

get('/') do
    db = db_connection('db/db.db')

    recipes = db.execute("SELECT recipes.id,recipes.title,recipes.user_id,users.username FROM recipes INNER JOIN users ON recipes.user_id = users.id;")

    p recipes

    slim(:index, locals:{recipes:recipes})
end

get('/error') do
    slim(:error)
end

get('/register') do
    slim(:register)
end

get('/login') do
    slim(:login)
end

get('/users/:id/profile') do
    db = db_connection('db/db.db')
    user_id = params[:id]

    user_data = db.execute("SELECT * FROM users WHERE id=(?)",user_id).first
    user_recipes = db.execute("SELECT title,id FROM recipes WHERE user_id=(?)",user_id)

    if user_data.nil?
        session[:message] = "user does not exist"
        redirect('/error')
    end

    slim(:"users/index", locals:{users_info:user_data,users_recipes:user_recipes})
end

get('/recipes/:id') do
    db = db_connection('db/db.db')
    recipe_id = params[:id]

    recipe_data = db.execute("SELECT * FROM recipes WHERE id=(?)",recipe_id).first

    if recipe_data.nil?
        session[:message] = "recipe does not exist"
        redirect('/error')
    end

    slim(:"recipes/index", locals:{recipes_info:recipe_data})
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