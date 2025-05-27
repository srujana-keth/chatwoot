class Whatsapp::EmbeddedController < ApplicationController
  before_action :authenticate_user!
  before_action :check_authorization

  def new
    # Configuration endpoint for embedded signup initialization
    render json: {
      status: 'ready',
      app_id: GlobalConfig.get('WHATSAPP_APP_ID'),
      configuration_id: GlobalConfig.get('WHATSAPP_CONFIGURATION_ID'),
      partner_id: GlobalConfig.get('WHATSAPP_PARTNER_ID'),
      graph_api_version: GlobalConfig.get('WHATSAPP_GRAPH_API_VERSION') || 'v21.0'
    }
  end

  def embedded_signup
    # Handle the embedded signup completion from Facebook
    unless params[:business_id].present? && params[:waba_id].present?
      render json: { error: 'Missing required business information' }, status: :bad_request
      return
    end

    # Queue the background job to process the embedded signup
    job = Whatsapp::EmbeddedSignupJob.perform_later(
      account_id: Current.account.id,
      business_id: params[:business_id],
      waba_id: params[:waba_id],
      phone_number_id: params[:phone_number_id]
    )

    render json: {
      status: 'processing',
      job_id: job.job_id,
      message: 'WhatsApp Business Account is being configured'
    }
  rescue StandardError => e
    Rails.logger.error("WhatsApp embedded signup processing error: #{e.message}")
    render json: {
      error: 'Internal server error',
      message: e.message
    }, status: :internal_server_error
  end

  def callback
    # Legacy callback for OAuth flow (keeping for backward compatibility)
    unless params[:code].present?
      render json: { error: 'Authorization code is required' }, status: :bad_request
      return
    end

    if params[:error].present?
      Rails.logger.error("WhatsApp OAuth callback error: #{params[:error]} - #{params[:error_description]}")
      render json: {
        error: 'WhatsApp signup failed',
        message: params[:error_description] || params[:error]
      }, status: :unprocessable_entity
      return
    end

    # Queue the background job to handle the OAuth code exchange
    job = Whatsapp::EmbeddedSignupJob.perform_later(
      account_id: Current.account.id,
      code: params[:code]
    )

    render json: {
      status: 'processing',
      job_id: job.job_id,
      message: 'WhatsApp signup is being processed'
    }
  rescue StandardError => e
    Rails.logger.error("WhatsApp OAuth callback error: #{e.message}")
    render json: {
      error: 'Internal server error',
      message: e.message
    }, status: :internal_server_error
  end

  private

  def check_authorization
    authorize(Current.account, :update?)
  end
end
