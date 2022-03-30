
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative './model.rb'

enable :sessions

# setup


clear_message_routes = false

def db_connection(route)
    db = SQLite3::Database.new(route)
    db.results_as_hash = true
    return db
end

#clear session-cookies
before do
    if session[:message]
        if clear_message_routes
            session[:message] = nil
            clear_message_routes = false
        else
            clear_message_routes = true
        end
    end
end

#get routes

get('/') do
    db = db_connection('db/db.db')
    genres = []

    recipes = db.execute("SELECT recipes.id,recipes.title,recipes.user_id,users.username FROM recipes INNER JOIN users ON recipes.user_id = users.id")

    recipes.each do |index|
        genres << db.execute("SELECT genres.genre FROM recipes_genre_rel INNER JOIN genres ON recipes_genre_rel.genre_id = genres.id WHERE recipes_genre_rel.recipe_id=(?)", index['id'])
    end
    

    slim(:index, locals:{recipes:recipes,genres:genres})
end

get('/error') do
    slim(:error)
end

get('/register') do
    @register_texts = [" make tasty pancakes!"," make bread!"," live in harmony!","... um... cook rice?"," impress family and friends!", " avoid unforeseen consequences...!"]
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

get('/users/:id/edit') do
    user_id = params[:id]
    if user_id.to_i == session[:active_user_id].to_i

        slim(:"users/edit")
    else
        session[:message] = "you cannot edit someone elses profile!"
        slim(:error)
    end
end

get('/recipes/new') do
    if session[:active_user_role] != "guest" && session[:active_user_role] != nil
        slim(:"recipes/new")
    else
        session[:message] = "you have to be either verified or an admin to create recipes!"
        redirect('/error')
    end
end

get('/recipes/:id') do
    db = db_connection('db/db.db')
    recipe_id = params[:id]

    session[:recipe_id] = recipe_id

    recipe_data = db.execute("SELECT * FROM recipes WHERE id=(?)",recipe_id).first
    if recipe_data.nil?
        session[:message] = "recipe does not exist"
        redirect('/error')
    end

    recipe_data = recipe_data.merge(db.execute("SELECT username FROM users WHERE id=(?)",recipe_data["user_id"]).first)

    @comments = db.execute("SELECT comments.content,users.username,users.role,comments.date FROM comments INNER JOIN users ON comments.user_id = users.id WHERE recipe_id=(?)",recipe_id)

    slim(:"recipes/index", locals:{recipes_info:recipe_data})
end

get('/recipes/:id/edit') do
    db = db_connection('db/db.db')
    recipe_id = params[:id]

    owner_check = db.execute("SELECT user_id FROM recipes WHERE id=(?)",recipe_id).first['user_id']

    if session[:active_user_role] != "guest" && session[:active_user_role] != nil && owner_check == session[:active_user_id]
        @recipe_name = db.execute("SELECT title FROM recipes WHERE id=(?)",recipe_id).first['title']
        slim(:"recipes/edit",locals:{recipe_id:recipe_id})
    else
        session[:message] = "you have to be either verified or an admin to edit recipes! ...and also the owner of the recipe."
        redirect('/error')
    end
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

post('/login') do
    db = db_connection('db/db.db')
    username = params[:username]
    password = params[:password]

    login_check = db.execute("SELECT * FROM users WHERE username=(?)",username).first

    if login_check != nil
        if BCrypt::Password.new(login_check["password"]) == (password + "salt")
            session[:active_user] = login_check['username']
            session[:active_user_id] = login_check['id']
            session[:active_user_role] = login_check['role']
            redirect('/')
        else
            session[:message] = "Login failed: invalid input"
            redirect('/login')
        end
    else
        session[:message] = "user does not exist"
        redirect('/login')
    end
end

post('/logout') do
    session[:active_user] = nil
    session[:active_user_id] = nil
    session[:active_user_role] = nil

    redirect('/')
end

post('/comment/new') do
    db = db_connection('db/db.db')
    comment = params[:comment]
    recipe_id = session[:recipe_id].to_i

    date = Time.now.strftime("%Y-%b-%d")
    p date

    db.execute("INSERT INTO comments(user_id,recipe_id,content,date) VALUES (?,?,?,?)",session[:active_user_id].to_i,recipe_id,comment,date)

    redirect("/recipes/#{recipe_id}")
end

post("/users/:id/update") do
    db = db_connection('db/db.db')
    user_id = params[:id]
    email = params[:email]

    if email.include?("@")
        db.execute("UPDATE users SET role='verified' WHERE id=(?)",user_id)
        session[:active_user_role] = db.execute("SELECT role FROM users WHERE id=(?)",user_id).first

        redirect("/users/#{user_id}/profile")
    else
        session[:message] = "you must enter an actual email adress"

        redirect("/users/#{user_id}/edit")
    end
end

post("/recipes") do
    db = db_connection('db/db.db')
    title = params[:title].to_s
    background = params[:background].to_s
    ingredients = params[:ingredients].to_s
    steps = params[:steps].to_s
    genre1 = params[:genre1].to_s
    genre2 = params[:genre2].to_s
    genre3 = params[:genre3].to_s

    db.execute("INSERT INTO recipes(title,info,ingredients,steps,user_id) VALUES (?,?,?,?,?)",title,background,ingredients,steps,session[:active_user_id])

    latest_recipe = db.execute("SELECT id FROM recipes ORDER BY id DESC").first

    genres_id = db.execute("SELECT id FROM genres WHERE genre IN (?,?,?)",genre1,genre2,genre3)

    genres_id.each do |genre|
        db.execute("INSERT INTO recipes_genre_rel(recipe_id,genre_id) VALUES (?,?)",latest_recipe['id'],genre['id'])
    end

    redirect("/users/#{session[:active_user_id]}/profile")
end

post('/recipes/:id/update') do
    db = db_connection('db/db.db')
    id = params[:id].to_i
    title = params[:title].to_s
    background = params[:background].to_s
    ingredients = params[:ingredients].to_s
    steps = params[:steps].to_s
    genre1 = params[:genre1].to_s
    genre2 = params[:genre2].to_s
    genre3 = params[:genre3].to_s
    delete = params[:delete].to_s

    if delete == "on"
        db.execute("DELETE FROM recipes WHERE id=(?)",id)

        db.execute("DELETE FROM recipes_genre_rel WHERE recipe_id=(?)",id)
    else
        db.execute("UPDATE recipes SET title=(?),info=(?),ingredients=(?),steps=(?) WHERE id=(?)",title,background,ingredients,steps,id)

        genres_id = db.execute("SELECT id FROM genres WHERE genre IN (?,?,?)",genre1,genre2,genre3)

        rel_id = db.execute("SELECT id FROM recipes_genre_rel WHERE recipe_id=(?)",id)

        genres_id.each_with_index do |genre,index|
            db.execute("UPDATE recipes_genre_rel SET genre_id=(?) WHERE recipe_id=(?) AND id=(?)",genre['id'],id,rel_id[index]['id'])
        end
    end

    redirect("/")
end