
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative './model.rb'

enable :sessions

# setup

clear_message_routes = false
$stress_array = []

def db_connection(route)
    db = SQLite3::Database.new(route)
    db.results_as_hash = true
    return db
end

def update_active_user(name,id,role)
    session[:active_user] = name
    session[:active_user_id] = id
    session[:active_user_role] = role
    return nil
end

def ghost_users(array)
    db = db_connection('db/db.db')
    array.each do |ary|
        name = db.execute("SELECT username FROM users WHERE id=(?)",ary['user_id']).first
        role = db.execute("SELECT role FROM users WHERE id=(?)",ary['user_id']).first
        if name != nil
            ary["username"] = name["username"]
            ary["role"] = role["role"]
        else
            ary["username"] = "an echo of the past"
            ary["role"] = "deleted"
        end
    end
end

def length_check(string,len)
    if string.length >= len
        return true
    else
        return false
    end
end

def time_check(time_array, time)
    if time_array.length == 2
        $stress_array = []
        if time_array[-1] - time_array[0] < time
            return true
        else
            return false
        end
    else
        return false
    end
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

    recipes = db.execute("SELECT id,title,user_id FROM recipes")

    ghost_users(recipes)

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
    slim(:"users/new")
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
        session[:message] = "Re-routing failed: user does not exist"
        redirect('/error')
    end

    slim(:"users/index", locals:{users_info:user_data,users_recipes:user_recipes})
end

get('/users/:id/edit') do
    user_id = params[:id]
    if user_id.to_i == session[:active_user_id].to_i

        slim(:"users/edit")
    else
        session[:message] = "Re-routing failed: you cannot edit someone elses profile!"
        slim(:error)
    end
end

get('/recipes/new') do
    if session[:active_user_role] != "guest" && session[:active_user_role] != nil
        slim(:"recipes/new")
    else
        session[:message] = "Re-routing failed: you have to be either verified or an admin to create recipes!"
        redirect('/error')
    end
end

get('/recipes/:id') do
    db = db_connection('db/db.db')
    recipe_id = params[:id]

    session[:recipe_id] = recipe_id

    recipe_data = db.execute("SELECT * FROM recipes WHERE id=(?)",recipe_id)
    if recipe_data.nil?
        session[:message] = "Re-routing failed: recipe does not exist"
        redirect('/error')
    end
    ghost_users(recipe_data)
    recipe_data = recipe_data.first

    @comments = db.execute("SELECT content,date,user_id FROM comments WHERE recipe_id=(?)",recipe_id)
    ghost_users(@comments)

    slim(:"recipes/index", locals:{recipes_info:recipe_data})
end

get('/recipes/:id/edit') do
    db = db_connection('db/db.db')
    recipe_id = params[:id]

    owner_check = db.execute("SELECT user_id FROM recipes WHERE id=(?)",recipe_id).first['user_id']

    if owner_check == session[:active_user_id] || session[:active_user_role] == "admin"
        @recipe_name = db.execute("SELECT title FROM recipes WHERE id=(?)",recipe_id).first['title']
        slim(:"recipes/edit",locals:{recipe_id:recipe_id})
    else
        session[:message] = "Re-routing failed: you have to be either be an admin or the owner to edit this recipe"
        redirect('/error')
    end
end

#post routes

post('/users') do
    db = db_connection('db/db.db')
    username = params[:username]
    password = params[:password]
    ver_password = params[:ver_password]

    if length_check(username,33)
        session[:message] = "Register failed: username too long, it must be shorter than 33 characters"
        redirect('/register')
    end

    if db.execute("SELECT username FROM users WHERE username=(?)",username).first != nil
        session[:message] = "Register failed: name already taken!"
        redirect('/register')
    end

    $stress_array << Time.now.to_i
    p $stress_array

    if time_check($stress_array,6)
        session[:message] = "Register failed: too much pressure"
        redirect('/register')
    end

    if password == ver_password
        salted_password = password + "salt"
        crypted_password = BCrypt::Password.create(salted_password)
        db.execute("INSERT INTO users(username,password,role) VALUES (?,?,?)",username,crypted_password,"guest")
        session[:message] = "User created!"
        redirect('/login')
    else
        session[:message] = "Register failed: password not equal to ver_password"
        redirect('/register')
    end
end

post('/login') do
    db = db_connection('db/db.db')
    username = params[:username]
    password = params[:password]

    login_check = db.execute("SELECT * FROM users WHERE username=(?)",username).first

    if login_check != nil
        if BCrypt::Password.new(login_check["password"]) == (password + "salt")
            update_active_user(login_check['username'],login_check['id'],login_check['role'])
            redirect('/')
        else
            session[:message] = "Login failed: invalid input"
            redirect('/login')
        end
    else
        session[:message] = "Login failed: user does not exist"
        redirect('/login')
    end
end

post('/logout') do
    update_active_user(nil,nil,nil)

    redirect('/')
end

post('/users/:id/update') do
    db = db_connection('db/db.db')
    user_id = params[:id]
    email = params[:email]
    new_username = params[:username]

    if email != nil
        if email.include?("@")
            db.execute("UPDATE users SET role='verified' WHERE id=(?)",user_id)
            db.execute("UPDATE users SET email=(?) WHERE id=(?)",email,user_id)
            session[:active_user_role] = db.execute("SELECT role FROM users WHERE id=(?)",user_id).first

            redirect("/users/#{user_id}/profile")
        else
            session[:message] = "User update failed: you must enter an actual email adress"

            redirect("/users/#{user_id}/edit")
        end
    end

    if length_check(new_username,33)
        session[:message] = "User update failed: new username too long, it must be shorter than 33 characters"
        redirect("/users/#{user_id}/edit")
    else
        db.execute("UPDATE users SET username=(?) WHERE id=(?)",new_username,user_id)
        session[:active_user] = new_username

        redirect("/users/#{user_id}/profile")
    end
end

post('/users/:id/delete') do
    db = db_connection('db/db.db')
    id = params[:id].to_i

    db.execute("DELETE FROM users WHERE id=(?)",id)
    update_active_user(nil,nil,nil)

    redirect('/')
end

post('/comment') do
    db = db_connection('db/db.db')
    comment = params[:comment]
    recipe_id = session[:recipe_id].to_i

    date = Time.now.strftime("%Y-%b-%d")

    db.execute("INSERT INTO comments(user_id,recipe_id,content,date) VALUES (?,?,?,?)",session[:active_user_id].to_i,recipe_id,comment,date)

    redirect("/recipes/#{recipe_id}")
end

post('/recipes') do
    db = db_connection('db/db.db')
    title = params[:title].to_s
    background = params[:background].to_s
    ingredients = params[:ingredients].to_s
    steps = params[:steps].to_s
    genre1 = params[:genre1].to_s
    genre2 = params[:genre2].to_s
    genre3 = params[:genre3].to_s

    if length_check(title,45)
        session[:message] = "New recipe failed: title is too long, it must be shorter than 45 characters"
        redirect('/recipes/new')
    end

    $stress_array << Time.now.to_i
    p $stress_array

    if time_check($stress_array,20)
        session[:message] = "New recipe failed: too much pressure"
        redirect('/recipes/new')
    end

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

    db.execute("UPDATE recipes SET title=(?),info=(?),ingredients=(?),steps=(?) WHERE id=(?)",title,background,ingredients,steps,id)

    genres_id = db.execute("SELECT id FROM genres WHERE genre IN (?,?,?)",genre1,genre2,genre3)

    rel_id = db.execute("SELECT id FROM recipes_genre_rel WHERE recipe_id=(?)",id)

    genres_id.each_with_index do |genre,index|
        db.execute("UPDATE recipes_genre_rel SET genre_id=(?) WHERE recipe_id=(?) AND id=(?)",genre['id'],id,rel_id[index]['id'])
    end

    redirect('/')
end

post ('/recipes/:id/delete') do
    db = db_connection('db/db.db')
    id = params[:id].to_i

    db.execute("DELETE FROM recipes WHERE id=(?)",id)
    db.execute("DELETE FROM recipes_genre_rel WHERE recipe_id=(?)",id)

    redirect('/')
end