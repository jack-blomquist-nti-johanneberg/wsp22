
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative './model.rb'

enable :sessions

# setup

clear_message_routes = false

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
    keyword = params[:search]

    slim(:index, locals:{recipes:ghost_users(get_recipes(keyword)[0]),genres:get_recipes(keyword)[1]})
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

get('/users/:id') do
    user_id = params[:id]

    slim(:"users/index", locals:{users_info:get_user(user_id)[0],users_recipes:get_user(user_id)[1]})
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
    recipe_id = params[:id]
    session[:recipe_id] = recipe_id

    get_comments(recipe_id)

    slim(:"recipes/index", locals:{recipes_info:get_recipe_data(recipe_id)})
end

get('/recipes/:id/edit') do
    recipe_id = params[:id]

    owner_check(recipe_id)['user_id']

    if owner_check(recipe_id)['user_id'] == session[:active_user_id] || session[:active_user_role] == "admin"
        @recipe_name = owner_check(recipe_id)['title']
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

            redirect("/users/#{user_id}")
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

        redirect("/users/#{user_id}")
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

    redirect("/users/#{session[:active_user_id]}")
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