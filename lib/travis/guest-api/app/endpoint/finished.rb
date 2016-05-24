require 'travis/guest-api/app/endpoint'

class Travis::GuestApi::App::Endpoint
  class Finished < Travis::GuestApi::App::Endpoint

    before do
      @msg_handler = env['msg_handler']
      @reporter = env['reporter']
    end

    post '/finished' do
       @msg_handler.call(job_id: @job_id, event: 'finished', reporter: @reporter, result: params['result'])
      { success: true }.to_json
    end

  end
end
