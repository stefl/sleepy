begin
  require 'memcached'
  HAS_MEMCACHE = true
rescue
  HAS_MEMCACHE = false
  puts "Sleepy with no Memcached"
end

require 'weary'

# This requires Memcached to be running on your system.
module Weary
  
  class Request
    
    def self.sleepy
      @@sleepy ||= Memcached.new
    end
    
    def sleepy
      self.class.sleepy
    end
    
    def round_time(integer, factor)
      return integer if(integer % factor == 0)
      return integer - (integer % factor)
    end
    
    def perform_sleepily(timeout=60*60*1000, &block)
      @on_complete = block if block_given?
      if HAS_MEMCACHE
        timeout = ENV["SLEEPY_TIMEOUT"] if defined?(ENV["SLEEPY_TIMEOUT"])
        response = perform_sleepily!(timeout)
      else
        response = perform
      end
      response.value
    end
    
    # Redefine the perform method
    def perform_sleepily!(timeout, &block)
      @on_complete = block if block_given?
      Thread.new {
        before_send.call(self) if before_send
        
        nap = sleepy.get("#{round_time(Time.new.to_i, timeout)}:#{uri}") rescue nil
        
        unless nap.blank?
          STDERR.puts "Return cached result #{nap.inspect}"
          nap
        else
          req = http.request(request)
          
          response = Response.new(req, self)
          begin
            if response.redirected?
              response = response.follow_redirect
            else
              on_complete.call(response) if on_complete
              response
            end
            if response.code && response.code == 200
              sleepy.set("#{round_time(Time.new.to_i, timeout)}:#{uri}", response)
              sleepy.set("0:#{uri}", response)
            end
          rescue
            sleepy.get("0:#{uri}") rescue nil
          end
          response
        end
      }
    end
  end
end