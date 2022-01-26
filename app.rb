
require 'sinatra'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions

get('/') do
    slim(:index)
end

get('/register') do
    slim(:register)
end

get('/login') do
    slim(:login)
end

get('/users/index') do
    slim(:"users/index")
end

post('/users/new') do
    redirect('/users/index')
end