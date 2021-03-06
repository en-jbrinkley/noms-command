require 'sinatra/base'
require 'json'

# Implement Do Not Call List Example REST application
# and static file server
class DNC < Sinatra::Application

    set :root, File.expand_path("#{File.dirname(__FILE__)}")
    enable :static, :sessions

    File.open(File.join(settings.root, 'dnc.pid'), 'w') {|f| f.puts Process.pid }

    def load_data
        JSON.load(File.open(File.join(settings.root, 'public', 'files', 'data.json')))
    end

    def write_data(data)
        File.open(File.join(settings.root, 'public', 'files', 'data.json'), 'w') { |fh| fh << data.to_json }
    end

    helpers do
        def require_auth
            return if authorized?
            headers['WWW-Authenticate'] = 'Basic realm="Authorization Required"'
            halt 401, "Not authorized\n"
        end

        def authorized?
            @auth ||=  Rack::Auth::Basic::Request.new(request.env)
            @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == ['testuser', 'testpass']
        end

        def generated_body(h={})
            JSON.pretty_generate({ 'generated' => Time.now.httpdate }.merge(h)) + "\n"
        end

        def require_cookie_auth
            return if cookie_authorized?
            redirect "/cookie/login?return_to=#{CGI.escape(request.path)}"
        end

        def cookie_authorized?
            session[:userid] == 'testuser'
        end
    end

    before do
        content_type 'application/json'
    end

    get '/cookie/login' do
        require_auth
        session[:userid] = @auth.credentials.first
        landing = params[:return_to] || '/cookie/home'
        redirect landing
    end

    get '/cookie/home' do
        require_cookie_auth
        generated_body({'cookie_user' => session[:userid] })
    end

    get '/cookie/logout' do
        old_userid = session[:userid]
        session[:userid] = nil
        generated_body({'message' => "#{old_userid} logged out"})
    end

    get '/readme' do
        redirect 'https://raw.githubusercontent.com/en-jbrinkley/noms-command/master/README.rst', 'README'
    end

    get '/dnc' do
        data = load_data
        if request.query_string.empty?
            [ 200, { 'Content-type' => 'application/json'},
                JSON.pretty_generate(data) ]
        else
            [ 200, { 'Content-type' => 'application/json' },
                JSON.pretty_generate(
                                     data.select do |item|
                                         params.keys.all? { |k| item[k.to_s] && item[k.to_s].to_s === params[k] }
                                     end)
            ]
        end
    end

    get '/dnc/:id' do
        data = load_data
        object = data.find { |e| e['id'] == params[:id].to_i }
        if object
            [ 200, { 'Content-type' => 'application/json' },
                JSON.pretty_generate(object) ]
        else
            404
        end
    end

    post '/dnc' do
        request.body.rewind
        new_object = JSON.parse request.body.read

        puts "POST for object: #{new_object.inspect}"

        data = load_data
        # How unsafe is this?
        new_object['id'] = data.map { |e| e['id'] }.max + 1
        data << new_object
        write_data data

        [ 201, { 'Content-type' => 'application/json' },
            JSON.pretty_generate(new_object) ]
    end

    put '/dnc/:id' do
        request.body.rewind
        new_object = JSON.parse request.body.read

        data = load_data
        new_data = data.reject { |e| e['id'] == params[:id].to_i }
        if new_data.size == data.size
            404
        else
            new_object['id'] = params[:id].to_i
            new_data << new_object
            write_data new_data

            [ 200, { 'Content-type' => 'application/json' },
                JSON.pretty_generate(new_object) ]
        end
    end

    delete '/dnc/:id' do
        data = load_data
        new_data = data.reject { |e| e['id'] == params[:id].to_i }

        if new_data.size == data.size
            404
        else
            write_data new_data
            204
        end
    end

    get '/alt/dnc.json' do
        redirect to('/dnc.json')
    end

    get '/auth/dnc.json' do
        require_auth
        redirect to('/dnc.json')
    end

    get '/auth/ok' do
        require_auth
        "SUCCESS"
    end

    # Caching client should let sit in cache
    # for 4s then refetch
    get '/static/max-age-4' do
        cache_control :max_age => 4
        generated_body
    end

    # Caching client must always revalidate
    # even within 4s
    get '/static/must-revalidate' do
        cache_control :must_revalidate, :max_age => 4
        expires 4
        etag "10"
        generated_body
    end

    # Caching client must never cache
    get '/static/no-cache' do
        cache_control :no_cache
        generated_body
    end

    # Caching client should let sit in cache
    # for 4s then refetch
    get '/static/expires-4' do
        expires 4
        generated_body
    end

    # Caching client should let sit in cache
    # for 4s then revalidate using If-Modified-Since
    get '/static/last-modified' do
        expires 4
        $static_time ||= Time.now
        last_modified $static_time
        generated_body
    end

    # Caching client should let sit in cache
    # for 4s then revalidate using If-None-Match
    get '/static/expires-4-changing' do
        expires 4
        etag Time.now.httpdate
        generated_body
    end

    # Caching client should let sit in cache
    # for 2s then revalidate using If-None-Match
    get '/static/expires-2-constant' do
        etag "10"
        expires 2
        generated_body
    end

    get '/static/long-cache' do
        etag "11"
        expires 100
        generated_body
    end

    get '/auth/cacheable' do
        require_auth
        expires 100
        etag "11"
        generated_body
    end

end
