require 'sinatra'
require 'stomp'
require 'cf-app-utils'
#require 'pretty_print'

DATA ||= {}

before do
  unless rabbitmq_creds('uris')
    halt 500, %{You must bind a RabbitMQ service instance to this application.

You can run the following commands to create an instance and bind to it:

  $ cf create-service p-rabbitmq development rabbitmq-instance
  $ cf bind-service <app-name> rabbitmq-instance}
  end
end

get '/ping' do

  begin
    client = Stomp::Client.new(
      :connect_headers => {
        "host" => rabbitmq_creds('vhost'),
        "accept-version" => "1.0,1.1,1.2"
      },
      :hosts => [
        :login => rabbitmq_creds('username'),
        :passcode => rabbitmq_creds('password'),
        :port => rabbitmq_creds('protocols')[:stomp][:port],
        :ssl => rabbitmq_creds('protocols')[:stomp][:ssl],
        :host => rabbitmq_creds('protocols')[:stomp][:host]],
      :reliable => true)

    status 200
    body 'OK'
  rescue Exception => e
    halt 500, "ERR:#{e}"
  end

end

get '/env' do
  status 200
  body "rabbitmq_url: #{rabbitmq_creds('protocols')[:stomp][:uris]}\n"
end

put '/queue/:name' do
  q = mq(params[:name])
  puts q

  if params[:data]
    client.publish(q, params[:data])

    status 201
    body 'SUCCESS'
  else
    status 400
    body 'NO-DATA'
  end
end

get '/queue/:name' do
  begin
    q = mq(params[:name])
    message = nil

    # make sure we are not currently subscribed to any queues
    client.unsubscribe(q)
    puts q

    begin
      client.subscribe(q) do |msg|
          message = msg
      end
      Timeout::timeout(2) do
        sleep 0.01 until message
      end
          
      client.unsubscribe(q)
      status 200
      body message.body
      
    rescue Timeout::Error
      client.unsubscribe(q)
      status 204
      body ""
    end


  rescue Exception => e
    halt 500, "ERR:#{e}"
  end
end

error do
  halt 500, "ERR:#{env['sinatra.error']}"
end

#############################################

def mq(name)
  "test.mq.#{name}"
end

def rabbitmq_creds(name)
  return nil unless ENV['VCAP_SERVICES']

  JSON.parse(ENV['VCAP_SERVICES'], :symbolize_names => true).values.map do |services|
    services.each do |s|
      begin
        return s[:credentials][name.to_sym]
      rescue Exception
      end
    end
  end
  nil
end


def client
  unless $client
    begin

      $client = Stomp::Client.new(
        :connect_headers => {
          "host" => rabbitmq_creds('vhost'),
          "accept-version" => "1.0,1.1,1.2"
        },
        :hosts => [
          :login => rabbitmq_creds('username'),
          :passcode => rabbitmq_creds('password'),
          :port => rabbitmq_creds('protocols')[:stomp][:port],
          :ssl => rabbitmq_creds('protocols')[:stomp][:ssl],
          :host => rabbitmq_creds('protocols')[:stomp][:host]],
        :reliable => true)

    rescue Exception => e
      halt 500, "ERR:#{e}"
    end
  end
  $client
end
