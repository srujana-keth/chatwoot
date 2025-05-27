class Whatsapp::EmbeddedSignupJob < ApplicationJob
  queue_as :medium

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(account_id:, code: nil, business_id: nil, waba_id: nil, phone_number_id: nil)
    account = Account.find(account_id)

    Rails.logger.tagged('WHATSAPP_SIGNUP') do
      Rails.logger.info("Starting embedded signup job for account #{account_id}")
    end

    service = Whatsapp::EmbeddedSignupService.new(
      account: account,
      code: code,
      business_id: business_id,
      waba_id: waba_id,
      phone_number_id: phone_number_id
    )
    channel = service.perform

    Rails.logger.tagged('WHATSAPP_SIGNUP') do
      Rails.logger.info("Successfully completed embedded signup for account #{account_id}, channel #{channel.id}")
    end

    # Broadcast success to frontend via ActionCable
    ActionCable.server.broadcast(
      "account_#{account_id}",
      {
        type: 'whatsapp_signup_completed',
        data: {
          channel_id: channel.id,
          inbox_id: channel.inbox&.id,
          status: 'success'
        }
      }
    )

    channel
  rescue StandardError => e
    Rails.logger.tagged('WHATSAPP_SIGNUP') do
      Rails.logger.error("Embedded signup job failed for account #{account_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end

    # Broadcast failure to frontend
    ActionCable.server.broadcast(
      "account_#{account_id}",
      {
        type: 'whatsapp_signup_failed',
        data: {
          error: e.message,
          status: 'failed'
        }
      }
    )

    raise e
  end
end
