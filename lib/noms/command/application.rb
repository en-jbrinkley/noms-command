#!ruby

require 'noms/command/version'
require 'noms/command/window'
require 'noms/command/useragent'
require 'noms/command/error'
require 'noms/command/urinion'
require 'noms/command/formatter'
require 'noms/command/document'
require 'noms/command/xmlhttprequest'

require 'logger'
require 'mime-types'
require 'v8'

class NOMS

end

class NOMS::Command

end

class NOMS::Command::Application

    # Should user-agent actually be here?
    attr_accessor :window, :options,
        :type, :body, :useragent,
        :document

    def initialize(window, origin, argv, attrs={})
        @window = window             # A NOMS::Command::Window
        @document = nil
        @origin = NOMS::Command::URInion.parse(origin)
        if @origin.scheme == 'file' and @origin.host.nil?
            @origin.host = 'localhost'
        end
        @argv = argv
        @options = { }
        @type = nil

        if attrs[:logger]
            @log = attrs[:logger]
        else
            @log = Logger.new $stderr
            @log.level = Logger::WARN
            @log.level = Logger::DEBUG if (ENV['NOMS_DEBUG'] and ! ENV['NOMS_DEBUG'].empty?)
        end

        @log.debug "Application #{argv[0]} has origin: #{origin}"
        @useragent = NOMS::Command::UserAgent.new(@origin, :logger => @log)
    end

    def fetch!
        # Get content and build object, set @type
        case @origin.scheme
        when 'file'
            @type = (MIME::Types.of(@origin.path).first || MIME::Types['text/plain'].first).content_type
            @body = File.open(@origin.path, 'r') { |fh| fh.read }
        when 'data'
            @type = @origin.mime_type
            raise NOMS::Command::Error.new("data URLs must contain application/json") unless @type == 'application/json'
            @body = @origin.data
        when /^http/
            response = @useragent.get(@origin)
            if response.ok?
                # Unlike typical ReST data sources, this
                # should very rarely fail unless there is
                # a legitimate communication issue.
                @type = response.contenttype || 'text/plain'
                @body = response.content
            else
                raise NOMS::Command::Error.new("Failed to request #{@origin}: #{response.status} #{response.reason}")
            end
        else
            raise NOMS::Command::Error.new("noms command #{@argv[0].inspect} not found: not a URL or bookmark")
        end

        case @type
        when /^(application|text)\/(x-|)json/
            @body = JSON.parse(@body)
            if @body.has_key? '$doctype'
                @type = @body['$doctype']
                @log.debug "Treating as #{@type} document"
                @document = NOMS::Command::Document.new @body
                @document.argv = @argv
                @document.exitcode = 0
            else
                @log.debug "Treating as raw object (no '$doctype')"
                @type = 'noms-raw'
            end
        end
    end

    def exitcode
        @document ? @document.exitcode : 0
    end

    def render!
        if @document and @document.script
            @v8 = V8::Context.new
            # Set up same-origin context and stuff--need
            # Ruby objects to do XHR and limit local I/O
            @window.document = @document
            @v8[:window] = @window
            @v8[:document] = @document
            @v8[:XMLHttpRequest] = NOMS::Command::XMLHttpRequest
            @document.script.each do |script|
                if script.respond_to? :has_key? and script.has_key? '$source'
                    # Parse relative URL and load
                    response = @useragent.get(script['$source'])
                    if response.ok?
                        case response.contenttype
                        when /^(application|text)\/(x-|)javascript/
                            begin
                                @v8.eval response.content
                            rescue StandardError => e
                                @log.warn "Javascript error: #{e.message}"
                                @log.debug e.backtrace.join("\n")
                            end
                        else
                            @log.warn "Unsupported script type '#{response.contenttype.inspect}' " +
                                "for script from #{script['$source'].inspect}"
                        end
                    else
                        @log.warn "Couldn't load script from #{script['$source'].inspect}: #{response.status} #{response.reason}"
                        @log.debug "Body of unsuccessful request: #{response.body}"
                    end
                else
                    # It's javascript text
                    begin
                        @v8.eval script
                    rescue StandardError => e
                        @log.warn "Javascript error: #{e.message}"
                        @log.debug e.backtrace.join("\n")
                    end
                end
            end
        end
    end

    def display
        case @type
        when 'noms-v2'
            NOMS::Command::Formatter.new(@document.body).render
        when 'noms-raw'
            @body.to_yaml
        when /^text(\/|$)/
            @body
        else
            if @window.isatty
                # Should this be here?
                @log.warn "Unknown data of type '#{@type}' not sent to terminal"
            else
                @body
            end
        end
    end

end
