
$stress_array = []

# Establishes a connection to the database
#
# @param [String] route
#
# @return [SQLite3::Database] allowing communications with the database
def db_connection(route)
    db = SQLite3::Database.new(route)
    db.results_as_hash = true
    return db
end

# Updates information about visible users to decide if they are deleted or not
#
# @param [String] array
#
# @return [Array] with some elements being replaced if users have been deleted
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
    return array
end

# Checks the length of a string
#
# @param [String] string
# @param [Integer] len
#
# @return [Boolean] based on if the inputed string was too long or not
def length_check(string,len)
    if string.length >= len
        return true
    else
        return false
    end
end

# Checks if the time between two events is too great
#
# @param [Array] time_array
# @param [String] time
#
# @return [Boolean] based on if the taken time was too long or not
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

# Checks if recipe exists and gives information if it does
#
# @param [Integer] id
#
# @return [Hash] 
#   * :user_id [Integer] the id of the user
#   * :title [String] the title of the recipe
def owner_check_recipe(id)
    db = db_connection('db/db.db')
    return db.execute("SELECT user_id,title FROM recipes WHERE id=(?)",id).first
end

# Checks if username is avaliable and gives information if it does
#
# @param [String] username
#
# @return [Hash] 
#   * :username [String] the username
def username_check(username)
    db = db_connection('db/db.db')
    return db.execute("SELECT username FROM users WHERE username=(?)",username).first
end

# Logins the user if the password is correct
#
# @param [String] username
# @param [String] password
#
# @return [Array] containing both a boolean and an error message 
def login_check(username,password)
    db = db_connection('db/db.db')
    login_check = db.execute("SELECT * FROM users WHERE username=(?)",username).first

    if login_check != nil
        if BCrypt::Password.new(login_check["password"]) == (password + "salt")
            update_active_user(login_check['username'],login_check['id'],login_check['role'])
            return true
        else
            return false,"Login failed: wrong password"
        end
    else
        return false,"Login failed: user does not exist"
    end
end

# Checks if the email is in a correct format
#
# @param [String] email
# @param [Integer] id
#
# @return [Array] containing both a boolean and the updated role if true
def email_check(email,id)
    db = db_connection('db/db.db')

    if email.include?("@")
        db.execute("UPDATE users SET role='verified' WHERE id=(?)",id)
        db.execute("UPDATE users SET email=(?) WHERE id=(?)",email,id)
        return true,db.execute("SELECT role FROM users WHERE id=(?)",id).first
    else
        return false
    end
end

# Selects the recipes based on a keyword
#
# @param [String] keyword
#
# @return [Array] containing both the recipe information and genres for the recipes
def get_recipes(keyword)
    db = db_connection('db/db.db')
    genres = []

    if keyword == "" || keyword == nil
        recipes = db.execute("SELECT id,title,user_id FROM recipes")
    else
        recipes = db.execute("SELECT id,title,user_id FROM recipes WHERE title=(?)",keyword)
    end

    recipes.each do |index|
        genres << db.execute("SELECT genres.genre FROM recipes_genre_rel INNER JOIN genres ON recipes_genre_rel.genre_id = genres.id WHERE recipes_genre_rel.recipe_id=(?)", index['id'])
    end

    return recipes,genres
end

# Finds the user page
#
# @param [Integer] id
#
# @return [Array] containing both user data and user recipes, or [Nil] if there is no data
def get_user(id)
    db = db_connection('db/db.db')
    user_data = db.execute("SELECT * FROM users WHERE id=(?)",id).first
    user_recipes = db.execute("SELECT title,id FROM recipes WHERE user_id=(?)",id)

    return user_data,user_recipes
end

# Retrieves data about a recipe
#
# @param [Integer] id
#
# @return [Hash]
#   * :id [Integer] the id of the recipe
#   * :title [String] the title of the recipe
#   * :info [String] the background of the recipe
#   * :ingredients [String] the ingredients of the recipe
#   * :steps [String] the steps of the recipe
#   * :user_id [Integer] the id of the recipe
def get_recipe_data(id)
    db = db_connection('db/db.db')
    recipe_data = db.execute("SELECT * FROM recipes WHERE id=(?)",id)

    ghost_users(recipe_data)

    return recipe_data.first
end

# Retrieves the comments
#
# @param [Integer] id
#
# @return [Nil]
def get_comments(id)
    db = db_connection('db/db.db')
    @comments = db.execute("SELECT content,date,user_id FROM comments WHERE recipe_id=(?)",id)

    ghost_users(@comments)

    return nil
end

# Creates a new user
#
# @param [String] username
# @param [String] password
# @param [String] ver_password
#
# @return [Boolean] based on password was equal to ver_password
def user_creation(username,password,ver_password)
    db = db_connection('db/db.db')

    if password == ver_password
        salted_password = password + "salt"
        crypted_password = BCrypt::Password.create(salted_password)
        db.execute("INSERT INTO users(username,password,role) VALUES (?,?,?)",username,crypted_password,"guest")
        return true
    else
        return false
    end
end

# Changes the username of a user
#
# @param [String] new_username
# @param [Integer] id
#
# @return [Boolean] since the username can be too long
def change_username(new_username,id)
    db = db_connection('db/db.db')

    if length_check(new_username,33)
        return false
    else
        db.execute("UPDATE users SET username=(?) WHERE id=(?)",new_username,id)
        return true
    end
end

# Deletes a user
#
# @param [Integer] id
#
# @return [Nil]
def delete_user(id)
    db = db_connection('db/db.db')

    db.execute("DELETE FROM users WHERE id=(?)",id)

    return nil
end

# Creates a new comment
#
# @param [Integer] recipe_id
# @param [String] comment
# @param [String] date
#
# @return [Nil]
def post_comment(recipe_id,comment,date,user_id)
    db = db_connection('db/db.db')

    db.execute("INSERT INTO comments(user_id,recipe_id,content,date) VALUES (?,?,?,?)",user_id,recipe_id,comment,date)

    return nil
end

# Creates a new recipe
#
# @param [String] title
# @param [String] background
# @param [String] ingredients
# @param [String] steps
# @param [String] genre1
# @param [String] genre2
# @param [String] genre3
#
# @return [Nil]
def post_recipe(title,background,ingredients,steps,genre1,genre2,genre3,user_id)
    db = db_connection('db/db.db')

    db.execute("INSERT INTO recipes(title,info,ingredients,steps,user_id) VALUES (?,?,?,?,?)",title,background,ingredients,steps,user_id)

    latest_recipe = db.execute("SELECT id FROM recipes ORDER BY id DESC").first

    genres_id = db.execute("SELECT id FROM genres WHERE genre IN (?,?,?)",genre1,genre2,genre3)

    genres_id.each do |genre|
        db.execute("INSERT INTO recipes_genre_rel(recipe_id,genre_id) VALUES (?,?)",latest_recipe['id'],genre['id'])
    end

    return nil
end

# Updates a recipe
#
# @param [Integer] id
# @param [String] title
# @param [String] background
# @param [String] ingredients
# @param [String] steps
# @param [String] genre1
# @param [String] genre2
# @param [String] genre3
#
# @return [Nil]
def change_recipe(id,title,background,ingredients,steps,genre1,genre2,genre3)
    db = db_connection('db/db.db')

    db.execute("UPDATE recipes SET title=(?),info=(?),ingredients=(?),steps=(?) WHERE id=(?)",title,background,ingredients,steps,id)

    genres_id = db.execute("SELECT id FROM genres WHERE genre IN (?,?,?)",genre1,genre2,genre3)

    rel_id = db.execute("SELECT id FROM recipes_genre_rel WHERE recipe_id=(?)",id)

    genres_id.each_with_index do |genre,index|
        db.execute("UPDATE recipes_genre_rel SET genre_id=(?) WHERE recipe_id=(?) AND id=(?)",genre['id'],id,rel_id[index]['id'])
    end

    return nil
end

# Deletes a recipe
#
# @param [Integer] id
#
# @return [Nil]
def delete_recipe(id)
    db = db_connection('db/db.db')

    db.execute("DELETE FROM recipes WHERE id=(?)",id)
    db.execute("DELETE FROM recipes_genre_rel WHERE recipe_id=(?)",id)

    return nil
end