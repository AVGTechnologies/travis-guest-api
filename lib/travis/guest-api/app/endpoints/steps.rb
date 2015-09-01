require 'travis/guest-api/app/base'

class Travis::GuestApi::App::Endpoints
  class Steps < Travis::GuestApi::App::Base
    before do
      @job_id = env['job_id']
      @reporter = env['reporter']
    end

    post '/steps' do
      halt 422, {
        error: 'Keys name, classname, result are mandatory!'
      }.to_json unless params['name'] && params['classname'] && params['result']
      params['uuid'] = SecureRandom.uuid
      sanitized_payload = params.slice(
        'uuid',
        'name',
        'classname',
        'result',
        'duration',
        'test_data')
      @reporter.send_tresult(@job_id, sanitized_payload)
      Travis::GuestApi.cache.set(@job_id, params['uuid'], sanitized_payload)
      sanitized_payload.to_json
    end

    get '/steps/:uuid' do
      cached_step = Travis::GuestApi.cache.get(@job_id, params[:uuid])
      halt 403, error: 'Requested step could not be found.' unless cached_step
      cached_step.to_json
    end

    put '/steps/:uuid' do
      sanitized_payload = params.slice(
        'name',
        'classname',
        'result',
        'duration',
        'test_data')
      @reporter.send_tresult_update(@job_id, sanitized_payload)
      # Cache.put(@job_id, payload['uuid'], sanitized_payload)
    end
  end
end