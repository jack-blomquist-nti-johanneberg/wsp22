
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'
require_relative './model.rb'

enable :sessions

clear_message_routes = false

# Clears the message cookie every other re-route
#
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

# Displays Landing Page
#
# @see Model#ghost_users
# @see Model#get_recipes
get('/') do
    keyword = params[:search]

    slim(:index, locals:{recipes:ghost_users(get_recipes(keyword)[0]),genres:get_recipes(keyword)[1]})
end

# Displays Error Page
#
get('/error') do
    slim(:error)
end

# Displays Register Page
#
# @register_texts [Array] texts, Texts that can appear when routing to the Register page
get('/register') do
    @register_texts = [" make tasty pancakes!"," make bread!"," live in harmony!","... um... cook rice?"," impress family and friends!", " avoid unforeseen consequences...!"]
    slim(:"users/new")
end

# Displays Login Page
#
get('/login') do
    slim(:login)
end

# Displays a User Page
#
# @param [Integer] user_id, the ID of the user who's page you are on
#
# @see Model#get_user
get('/users/:id') do
    user_id = params[:id].to_i

    slim(:"users/index", locals:{users_info:get_user(user_id)[0],users_recipes:get_user(user_id)[1]})
end

# Displays the Edit Page for a user
#
# @param [Integer] user_id, the ID of your user
get('/users/:id/edit') do
    user_id = params[:id].to_i
    if user_id == session[:active_user_id]
        slim(:"users/edit")
    else
        session[:message] = "Re-routing failed: you cannot edit someone elses profile!"
        slim(:error)
    end
end

# Displays the Recipe Page for making new recipes
#
get('/recipes/new') do
    if session[:active_user_role] != "guest" && session[:active_user_role] != nil
        slim(:"recipes/new")
    else
        session[:message] = "Re-routing failed: you have to be either verified or an admin to create recipes!"
        redirect('/error')
    end
end

# Displays a Recipe Page
#
# @param [Integer] recipe_id, the ID for the recipe
#
# @see Model#get_comments
# @see Model#get_recipe_data
get('/recipes/:id') do
    recipe_id = params[:id].to_i
    session[:recipe_id] = recipe_id

    get_comments(recipe_id)

    if get_recipe_data(recipe_id).nil?
        session[:message] = "Re-routing failed: recipe does not exist"
        redirect('/error')
    end

    slim(:"recipes/index", locals:{recipes_info:get_recipe_data(recipe_id)})
end

# Displays the Recipe Edit Page
#
# @param [Integer] recipe_id, the ID for the recipe
#
# @see Model#owner_check
get('/recipes/:id/edit') do
    recipe_id = params[:id]

    if owner_check(recipe_id).class == NilClass
        session[:message] = "Re-routing failed: recipe does not exist"
        redirect('/error')
    else
        if owner_check(recipe_id)['user_id'] == session[:active_user_id] || session[:active_user_role] == "admin"
            @recipe_name = owner_check(recipe_id)['title']
            slim(:"recipes/edit",locals:{recipe_id:recipe_id})
        else
            session[:message] = "Re-routing failed: you have to be either be an admin or the owner to edit this recipe"
            redirect('/error')
        end
    end
end

# Creates a new user and redirects to '/register'
#
# @param [String] username, the username for the new user
# @param [String] password, the password for the new user
# @param [String] ver_password, the verification of the password
#
# @see Model#length_check
# @see Model#username_check
# @see Model#time_check
# @see Model#user_creation
post('/users') do
    username = params[:username]
    password = params[:password]
    ver_password = params[:ver_password]

    if length_check(username,33)
        session[:message] = "Register failed: username too long, it must be shorter than 33 characters"
        redirect('/register')
    end

    if username_check(username) != nil
        session[:message] = "Register failed: name already taken!"
        redirect('/register')
    end

    $stress_array << Time.now.to_i

    if time_check($stress_array,6)
        session[:message] = "Register failed: too much pressure"
        redirect('/register')
    end

    if user_creation(username,password,ver_password)
        session[:message] = "User created!"
        redirect('/login')
    else
        session[:message] = "Register failed: password not equal to verify password"
        redirect('/register')
    end
end

# Logins the user and updates sessions and redirects 'login' or '/'
#
# @param [String] username, the username for the user
# @param [String] password, the password for the user
#
# @see Model#login_check
post('/login') do
    username = params[:username]
    password = params[:password]

    if login_check(username,password) == true
        redirect('/')
    else
        session[:message] = login_check(username,password)[-1]
        redirect('/login')
    end
end

# Logouts the user and clears sessions and redirects to '/'
#
# @see Model#update_active_user
post('/logout') do
    update_active_user(nil,nil,nil)

    redirect('/')
end

# Updates a user and redirects either to "/users/#{user_id}/edit" or "/users/#{user_id}"
#
# @param [Integer] user_id, the ID of the user being edited
# @param [String] email, the email of the user
# @param [String] new_username, the new username
#
# @see Model#email_check
# @see Model#update_active_user
# @see Model#change_username
post('/users/:id/update') do
    user_id = params[:id].to_i
    email = params[:email]
    new_username = params[:username]

    if email != nil
        if not(email_check(email,user_id))
            session[:message] = "User update failed: you must enter an actual email adress"
            redirect("/users/#{user_id}/edit")
        else
            update_active_user(session[:active_user],session[:active_user_id],email_check(email,user_id)[-1])
            redirect("/users/#{user_id}")
        end
    end

    if change_username(new_username,user_id)
        session[:active_user] = new_username
        redirect("/users/#{user_id}")
    else
        session[:message] = "User update failed: new username too long, it must be shorter than 33 characters"
        redirect("/users/#{user_id}/edit")
    end
end

# Deletes the logged in user and redirects to '/'
#
# @param [Integer] id, the ID of the user
#
# @see Model#delete_user
# @see Model#update_active_user
post('/users/:id/delete') do
    id = params[:id].to_i

    delete_user(id)
    update_active_user(nil,nil,nil)

    redirect('/')
end

# Creates a new comment and redirects to "/recipes/#{recipe_id}"
#
# @param [String] comment, the content of the comment
# @param [Integer] recipe_id, the ID of the recipe being commented on
#
# @see Model#post_comment
post('/comment') do
    comment = params[:comment]
    recipe_id = session[:recipe_id].to_i
    date = Time.now.strftime("%Y-%b-%d")

    post_comment(recipe_id,comment,date)

    redirect("/recipes/#{recipe_id}")
end

# Creates a new recipe and redirects to "/users/#{session[:active_user_id]}"
#
# @param [String] title, the title of the recipe
# @param [String] background, the background of the recipe
# @param [String] ingredients, the ingredients of the recipe
# @param [String] steps, the steps of the recipe
# @param [String] genre1, the first genre of the recipe
# @param [String] genre2, the second genre of the recipe
# @param [String] genre3, the third genre of the recipe
#
# @see Model#length_check
# @see Model#time_check
# @see Model#post_recipe
post('/recipes') do
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

    if time_check($stress_array,20)
        session[:message] = "New recipe failed: too much pressure"
        redirect('/recipes/new')
    end

    post_recipe(title,background,ingredients,steps,genre1,genre2,genre3)

    redirect("/users/#{session[:active_user_id]}")
end

# Updates a recipe and redirects to '/'
#
# @param [Integer] id, the id of the recipe
# @param [String] title, the title of the recipe
# @param [String] background, the background of the recipe
# @param [String] ingredients, the ingredients of the recipe
# @param [String] steps, the steps of the recipe
# @param [String] genre1, the first genre of the recipe
# @param [String] genre2, the second genre of the recipe
# @param [String] genre3, the third genre of the recipe
#
# @see Model#change_recipe
post('/recipes/:id/update') do
    id = params[:id].to_i
    title = params[:title].to_s
    background = params[:background].to_s
    ingredients = params[:ingredients].to_s
    steps = params[:steps].to_s
    genre1 = params[:genre1].to_s
    genre2 = params[:genre2].to_s
    genre3 = params[:genre3].to_s

    change_recipe(id,title,background,ingredients,steps,genre1,genre2,genre3)

    redirect('/')
end

# Deletes a recipe and redirects to '/'
#
# @param [Integer] id, the id of the recipe
#
# @see Model#delete_recipe
post('/recipes/:id/delete') do
    id = params[:id].to_i

    delete_recipe(id)

    redirect('/')
end