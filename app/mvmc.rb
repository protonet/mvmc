require 'sinatra/base'
require 'sinatra/i18n'
require 'sinatra/content_for'

class Mvmc < Sinatra::Base

  set :root,    File.join(File.dirname(__FILE__), '../')
  set :locales, File.join(File.dirname(__FILE__), '../', 'config/locales/en.yml')

  helpers Sinatra::ContentFor
  register Sinatra::I18n

  get '/' do
    redirect to('/dashboard'), 303
  end

  get '/dashboard' do
    haml :'dashboard/index'
  end

  get '/vms' do
    haml :'vms/index'
  end

  get '/isos' do
    haml :'isos/index'
  end

end
