require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require "sinatra/config_file"
require './models'
require 'yaml'
require 'backports'
require 'aws/s3'

if ENV['GITHUB_TOKEN']
	require './auth_live'
else 
	require './auth'
end

config_file 'datas/config.yml'

configure :development do  
  enable :logging
  DataMapper.auto_upgrade! 
  puts "dev :)".yellow
end

helpers do

  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    user = User.first(:username => "admin")
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [user.username, user.password]
  end

end

before do
    @categories = Category.all(:order => :name.asc)
end

def bake_html
#  File.open('tmp/index.html', 'w') do |f|
#   request = Rack::MockRequest.new(Sinatra::Application)
#   f.write request.get('/render').body
#  end

  AWS::S3::Base.establish_connection!(
    :access_key_id     => $aws_key,
    :secret_access_key => $aws_secret
  )
  
  puts "caching main page"
  request = Rack::MockRequest.new(Sinatra::Application)
  AWS::S3::S3Object.create('index.html',  request.get('/render').body, 'ofxaddons', :access => :public_read );

  puts "caching changes"  
  request = Rack::MockRequest.new(Sinatra::Application)
  AWS::S3::S3Object.create('changes.html',  request.get('/changes/render').body, 'ofxaddons', :access => :public_read );

  puts "caching contributors"
  request = Rack::MockRequest.new(Sinatra::Application)
  AWS::S3::S3Object.create('contributors.html',  request.get('/contributors/render').body, 'ofxaddons', :access => :public_read );

  puts "caching unsorted"
  request = Rack::MockRequest.new(Sinatra::Application)
  AWS::S3::S3Object.create('unsorted.html',  request.get('/unsorted/render').body, 'ofxaddons', :access => :public_read );
  
end

get "/bake" do
  protected!
  bake_html
end

get "/api/v1/all.json" do
  content_type :json
  repos = Repo.all(:not_addon => false, :is_fork => false, :category.not => nil, :deleted => false, :order => :name.asc)
  {"repos" => repos.collect{|r| r.to_json_hash}}.to_json  
end

get "/" do

  data = open("https://s3.amazonaws.com/ofxaddons/index.html")
  response.write(data.read)
  
  #old way
  #send_file File.join(settings.public_folder, 'index.html')
  
 #doesn't work 
 # open("https://s3.amazonaws.com/ofxaddons/index.html") do | chunk |
 #	  response.write( chunk )
 # end
 
end

get "/render" do
  @current = "addons"
  @categorized = Repo.all(:not_addon => false, :incomplete => false, :is_fork => false, :deleted => false, :category.not => nil, :order => :name.asc)
  @uncategorized = Repo.all(:not_addon => false, :is_fork => false, :deleted => false, :category => nil, :order => :name.asc)
  @repo_count = Repo.count(:conditions => ['not_addon = ? AND is_fork = ? AND deleted = ? AND incomplete = ? AND category_id IS NOT NULL', 'false', 'false', 'false', 'false'])
  erb :repos
end

get "/changes" do 
  data = open("https://s3.amazonaws.com/ofxaddons/changes.html")
  response.write(data.read)
end

get "/changes/render" do  
  @current = "changes"
  @most_recent = Repo.all(:not_addon => false, :is_fork => false, :deleted => false, :category.not => nil, :order => [:last_pushed_at.desc]) 
  erb :changes
end

# update all
put "/repos/update_all" do
  protected!
  params[:repos].each do |r|
    @repo = Repo.get(r[0])
    rps = params[:repos][r[0]].select {|k,v| puts "new k #{k} v #{v}"; not v.eql? ""}
    val = @repo.update(rps)
  end

  redirect "/admin"
end

put "/repos/:repo_id" do
  protected!
  @repo = Repo.get(params[:repo_id])
  @repo.update(params[:repo])
  bake_html
  redirect "/admin"
end

get "/repos/:repo_id" do
  @uncategorized = Repo.all(:not_addon => false, :is_fork => false, :category => nil, :deleted => false, :order => :name.asc)
  @repo = Repo.get(params[:repo_id])
  erb :repo
end

get "/admin/" do
  protected!
  @not_addons = Repo.all(:not_addon => true, :deleted => false, :order => :name.asc)
  repos = Repo.all(:not_addon => false, :is_fork => false, :deleted => false, :order => :name.asc)

  @incomplete = repos.select{|r| r.incomplete}
  @uncategorized = repos.select{|r| r.category.nil? and not r.incomplete}
  @categorized = repos.partition{|r| not r.category.nil? and not r.incomplete}
  
  erb :admin
end

get "/howto/" do
  @current = "howto"
  erb :howto
end

get "/users/:user_name" do
  @current = "contributors"
  @user = params[:user_name]
  @user_data = Repo.first(:owner => params[:user_name], :not_addon => false, :is_fork => false, :deleted => false)
  @user_repos = Repo.all( :owner => params[:user_name], :not_addon => false, :is_fork => false, :deleted => false, :order => [:followers.desc])
  erb :user
end

get "/contributors" do
  data = open("https://s3.amazonaws.com/ofxaddons/contributors.html")
  response.write(data.read)
end

get "/contributors/render" do
  @current = "contributors"
  @contributors = Repo.all(:not_addon => false, :is_fork => false, :deleted => false, :category.not => nil, :order => :name.asc)
  @contributors = @contributors.uniq {|r| r.owner}
  erb :contributors
end

get "/unsorted" do
  data = open("https://s3.amazonaws.com/ofxaddons/unsorted.html")
  response.write(data.read)
end

get "/unsorted/render" do
  @current = "unsorted"
  @uncategorized = Repo.all(:category => nil, :not_addon => false, :is_fork => false, :deleted => false, :order => :name.asc)
  @incomplete = Repo.all(:incomplete => true, :not_addon => false, :is_fork => false, :deleted => false, :order => :name.asc)
  erb :unsorted
end
