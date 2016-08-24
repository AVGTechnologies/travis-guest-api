require 'travis/guest-api/app/base'
require "sinatra/namespace"
require 'ostruct'
require 'rack/test'

class Travis::GuestApi::App::Middleware
  class Rewrite < Travis::GuestApi::App::Base

    register Sinatra::Namespace

    V1_PREFIX = '/api/v1'
    V2_PREFIX = '/api/v2'
    JOB_ID_PATTERN = %r{/api/v\d+/jobs/(\d+)}

    namespace V1_PREFIX do

      #before do
      #  Travis.logger.debug ">> #{env['REQUEST_METHOD']} #{env['PATH_INFO']} params: #{params.inspect}"
      #end

      before '/machines/logs/message' do
        rewrite_logs_v1
      end

      before '/machines/logs/attachement' do
        rewrite_attachments_v1
      end

      before '/machines/networks' do
        rewrite_networks_v1
      end

      before '/machines/steps/:uuid', method: :put do
        rewrite_steps_v1
      end

      before '/machines/steps/:uuid', method: :patch do
        rewrite_steps_v1
      end


      before '/machines/steps', method: :post do
        rewrite_post_steps_v1
      end

      before '/machines/notifications' do
        rewrite_notifications_v1
      end
    end

    before JOB_ID_PATTERN do |job_id|
      rewrite_job_id_part(job_id.to_i)
    end

    def rewrite_job_id_part(job_id)
      if env['job_id'] && (env['job_id'] != job_id.to_i)
        halt 422, {
          error: 'Job_id specified both on startup and '\
                 'in the request but they do not match!'
        }.to_json
      end

      env['PATH_INFO'].sub!(JOB_ID_PATTERN, V2_PREFIX)
      @job_id = env['job_id'] = job_id
    end

    def rewrite_job_id_v1
      unless env['HTTP_JOBID']
        halt 422, { error: 'JobId header must be specified in form data.'}.to_json
      end

      job_id = env.delete('HTTP_JOBID').to_i

      halt 422, { error: 'JOB_ID has to be specified in header' }.to_json if job_id == 0

      if env['job_id'] && (env['job_id'] != job_id)
        halt 422, {
          error: 'Job_id specified both on startup and '\
                 'in the request but they do not match!'
        }.to_json
      end
      @job_id = env['job_id'] = job_id
      request.update_param 'job_id', job_id
    end

    def rewrite_logs_v1
      env['PATH_INFO'] = "#{V2_PREFIX}/logs"
      rewrite_job_id_v1
      request.update_param 'message', request.delete_param('messageText')
    end

    def rewrite_attachments_v1
      env['PATH_INFO'] = "#{V2_PREFIX}/attachments"
    end

    def rewrite_networks_v1
      env['PATH_INFO'] = "#{V2_PREFIX}/networks"
    end

    def rewrite_post_steps_v1
      env['PATH_INFO'] = "#{V2_PREFIX}/steps"
      rewrite_job_id_v1

      unless params['stepStack'] and
             params['stepStack'].is_a?(Array) and
             params['stepStack'].last
        halt 422,
        { error: 'Property "stepStack" must be an array '\
                 'containing step name as last element.' }.to_json
      end

      request.update_param 'name', params[:stepStack].last
      request.update_param 'classname', params[:stepStack][-2]
      request.delete_param(:stepStack)
    end

    def rewrite_steps_v1
      env['PATH_INFO'] = "#{V2_PREFIX}/steps/#{params[:uuid]}"
      rewrite_job_id_v1
      request.delete_param(:stepStack)
    end

    def rewrite_notifications_v1
      case params['status']
      when 'finished'
        env['REQUEST_METHOD'] = 'POST'
        env['PATH_INFO'] = "#{V2_PREFIX}/finished"
      when 'started'
        env['REQUEST_METHOD'] = 'POST'
        env['PATH_INFO'] = "#{V2_PREFIX}/started"
      else
        halt 501, "Status=#{params['status'].inspect} is not implemented"
      end
      rewrite_job_id_v1
    end


  end
end
