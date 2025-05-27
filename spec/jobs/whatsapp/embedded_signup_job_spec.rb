require 'rails_helper'

RSpec.describe Whatsapp::EmbeddedSignupJob, type: :job do
  let(:account) { create(:account) }
  let(:code) { 'auth_code_123' }
  let(:channel) { create(:channel_whatsapp, account: account) }
  let(:inbox) { create(:inbox, channel: channel, account: account) }

  before do
    allow(Whatsapp::EmbeddedSignupService).to receive(:new).and_return(service_double)
  end

  let(:service_double) { instance_double(Whatsapp::EmbeddedSignupService) }

  describe '#perform' do
    context 'when service succeeds' do
      before do
        allow(service_double).to receive(:perform).and_return(channel)
        allow(channel).to receive(:inbox).and_return(inbox)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it 'creates service with correct parameters' do
        expect(Whatsapp::EmbeddedSignupService).to receive(:new)
          .with(account: account, code: code)
          .and_return(service_double)

        described_class.perform_now(account_id: account.id, code: code)
      end

      it 'calls perform on the service' do
        expect(service_double).to receive(:perform).and_return(channel)
        described_class.perform_now(account_id: account.id, code: code)
      end

      it 'logs success message' do
        expect(Rails.logger).to receive(:tagged).with('WHATSAPP_SIGNUP').and_yield
        expect(Rails.logger).to receive(:info)
          .with("Starting embedded signup job for account #{account.id}")
        expect(Rails.logger).to receive(:info)
          .with("Successfully completed embedded signup for account #{account.id}, channel #{channel.id}")

        described_class.perform_now(account_id: account.id, code: code)
      end

      it 'broadcasts success via ActionCable' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "account_#{account.id}",
          {
            type: 'whatsapp_signup_completed',
            data: {
              channel_id: channel.id,
              inbox_id: inbox.id,
              status: 'success'
            }
          }
        )

        described_class.perform_now(account_id: account.id, code: code)
      end

      context 'when channel has no inbox' do
        before do
          allow(channel).to receive(:inbox).and_return(nil)
        end

        it 'broadcasts success without inbox_id' do
          expect(ActionCable.server).to receive(:broadcast).with(
            "account_#{account.id}",
            {
              type: 'whatsapp_signup_completed',
              data: {
                channel_id: channel.id,
                inbox_id: nil,
                status: 'success'
              }
            }
          )

          described_class.perform_now(account_id: account.id, code: code)
        end
      end
    end

    context 'when service fails' do
      let(:error_message) { 'Service failed' }
      let(:error) { StandardError.new(error_message) }

      before do
        allow(service_double).to receive(:perform).and_raise(error)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:tagged).with('WHATSAPP_SIGNUP').and_yield
        expect(Rails.logger).to receive(:error)
          .with("Embedded signup job failed for account #{account.id}: #{error_message}")
        expect(Rails.logger).to receive(:error).with(anything) # backtrace

        expect { described_class.perform_now(account_id: account.id, code: code) }
          .to raise_error(StandardError, error_message)
      end

      it 'broadcasts failure via ActionCable' do
        expect(ActionCable.server).to receive(:broadcast).with(
          "account_#{account.id}",
          {
            type: 'whatsapp_signup_failed',
            data: {
              error: error_message,
              status: 'failed'
            }
          }
        )

        expect { described_class.perform_now(account_id: account.id, code: code) }
          .to raise_error(StandardError)
      end

      it 're-raises the error' do
        expect { described_class.perform_now(account_id: account.id, code: code) }
          .to raise_error(StandardError, error_message)
      end
    end

    context 'when account not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect { described_class.perform_now(account_id: 99999, code: code) }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'job configuration' do
    it 'has the correct queue' do
      expect(described_class.queue_name).to eq('medium')
    end

    it 'retries on standard errors' do
      # This tests that retry_on is configured properly
      expect(described_class.retry_on_is_configured_for?(StandardError)).to be_truthy
    end
  end

  describe 'retry behavior' do
    let(:error) { StandardError.new('Temporary failure') }

    before do
      allow(service_double).to receive(:perform).and_raise(error)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it 'retries the job on failure' do
      expect(Whatsapp::EmbeddedSignupService).to receive(:new).exactly(3).times
        .and_return(service_double)

      # Perform the job and expect it to retry
      perform_enqueued_jobs do
        expect { described_class.perform_later(account_id: account.id, code: code) }
          .to raise_error(StandardError)
      end
    end
  end
end