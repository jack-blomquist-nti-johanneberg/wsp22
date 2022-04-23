
# Setup
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
    return array
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

# Get metoder
def get_recipes(keyword)
    db = db_connection('db/db.db')
    genres = []

    if keyword == ""
        recipes = db.execute("SELECT id,title,user_id FROM recipes")
    else
        recipes = db.execute("SELECT id,title,user_id FROM recipes WHERE title=(?)",keyword)
    end

    recipes.each do |index|
        genres << db.execute("SELECT genres.genre FROM recipes_genre_rel INNER JOIN genres ON recipes_genre_rel.genre_id = genres.id WHERE recipes_genre_rel.recipe_id=(?)", index['id'])
    end

    return recipes,genres
end

def get_user(id)
    db = db_connection('db/db.db')
    user_data = db.execute("SELECT * FROM users WHERE id=(?)",id).first
    user_recipes = db.execute("SELECT title,id FROM recipes WHERE user_id=(?)",id)

    if user_data.nil?
        session[:message] = "Re-routing failed: user does not exist"
        redirect('/error')
    end

    return user_data,user_recipes
end

def get_recipe_data(id)
    db = db_connection('db/db.db')
    recipe_data = db.execute("SELECT * FROM recipes WHERE id=(?)",id)

    if recipe_data.nil?
        session[:message] = "Re-routing failed: recipe does not exist"
        redirect('/error')
    end

    ghost_users(recipe_data)

    return recipe_data.first
end

def get_comments(id)
    db = db_connection('db/db.db')
    @comments = db.execute("SELECT content,date,user_id FROM comments WHERE recipe_id=(?)",id)

    ghost_users(@comments)
end

def owner_check(id)
    db = db_connection('db/db.db')
    return db.execute("SELECT user_id,title FROM recipes WHERE id=(?)",id).first
end

# Post metoder