class Whatsapp::EmbeddedSignupService
  include Rails.application.routes.url_helpers

  def initialize(account:, code: nil, business_id: nil, waba_id: nil, phone_number_id: nil)
    @account = account
    @code = code
    @business_id = business_id
    @waba_id = waba_id
    @phone_number_id = phone_number_id
  end

  def perform
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Starting embedded signup for account #{@account.id}") }

    if @code
      # OAuth flow (legacy)
      perform_oauth_flow
    elsif @business_id && @waba_id && @phone_number_id
      # New embedded signup flow
      perform_embedded_flow
    else
      raise ArgumentError, 'Either code or business_id/waba_id/phone_number_id must be provided'
    end
  rescue StandardError => e
    Rails.logger.tagged('WHATSAPP') { Rails.logger.error("Embedded signup failed: #{e.message}") }
    raise e
  end

  private

  def perform_oauth_flow
    access_token = exchange_code_for_token
    waba_info = fetch_waba_info(access_token)
    phone_info = fetch_phone_info(waba_info[:waba_id], access_token)

    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Retrieved WABA: #{waba_info[:waba_id]}, Phone: #{phone_info[:phone_number_id]}") }

    channel = create_or_update_channel(waba_info, phone_info, access_token)
    setup_webhooks(waba_info[:waba_id], access_token)

    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Successfully created/updated channel #{channel.id}") }

    channel
  end

  def perform_embedded_flow
    # Get access token using system user token
    system_user_token = get_system_user_token
    phone_info = fetch_phone_info_direct(@phone_number_id, system_user_token)
    business_info = fetch_business_info(@business_id, system_user_token)

    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Retrieved Business: #{@business_id}, WABA: #{@waba_id}, Phone: #{@phone_number_id}") }

    waba_info = { waba_id: @waba_id, business_name: business_info[:name] }

    channel = create_or_update_channel(waba_info, phone_info, system_user_token)
    setup_webhooks(@waba_id, system_user_token)

    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Successfully created/updated channel #{channel.id}") }

    channel
  end

  def get_system_user_token
    # Use app access token to get system user token
    app_id = GlobalConfig.get('WHATSAPP_APP_ID')['WHATSAPP_APP_ID']
    app_secret = GlobalConfig.get('WHATSAPP_APP_SECRET')['WHATSAPP_APP_SECRET']

    "#{app_id}|#{app_secret}"
  end

  def fetch_phone_info_direct(phone_number_id, access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Fetching phone info for #{phone_number_id}") }

    response = Faraday.get(
      "https://graph.facebook.com/v21.0/#{phone_number_id}",
      {
        access_token: access_token,
        fields: 'id,display_phone_number,code_verification_status'
      }
    )

    raise "Phone info fetch failed: #{response.body}" unless response.success?

    data = JSON.parse(response.body)

    {
      phone_number_id: data['id'],
      phone_number: data['display_phone_number'],
      verified: data['code_verification_status'] == 'VERIFIED'
    }
  end

  def fetch_business_info(business_id, access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Fetching business info for #{business_id}") }

    response = Faraday.get(
      "https://graph.facebook.com/v21.0/#{business_id}",
      {
        access_token: access_token,
        fields: 'name'
      }
    )

    if response.success?
      data = JSON.parse(response.body)
      { name: data['name'] || "WhatsApp Business #{business_id}" }
    else
      Rails.logger.tagged('WHATSAPP') { Rails.logger.warn("Business info fetch failed: #{response.body}") }
      { name: "WhatsApp Business #{business_id}" }
    end
  end

  def exchange_code_for_token
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info('Exchanging code for access token') }

    response = Faraday.post(
      'https://graph.facebook.com/v21.0/oauth/access_token',
      {
        client_id: ENV.fetch('WHATSAPP_APP_ID'),
        client_secret: ENV.fetch('WHATSAPP_APP_SECRET'),
        code: @code
      },
      { 'Content-Type' => 'application/x-www-form-urlencoded' }
    )

    raise "Token exchange failed: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    raise "No access token in response: #{data}" unless data['access_token']

    data['access_token']
  end

  def fetch_waba_info(access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info('Fetching WABA information') }

    response = Faraday.get(
      'https://graph.facebook.com/v21.0/debug_token',
      {
        input_token: access_token,
        access_token: "#{ENV.fetch('WHATSAPP_APP_ID')}|#{ENV.fetch('WHATSAPP_APP_SECRET')}"
      }
    )

    raise "WABA info fetch failed: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    granular_scopes = data.dig('data', 'granular_scopes')

    waba_scope = granular_scopes&.find { |scope| scope['scope'] == 'whatsapp_business_management' }
    raise 'No WABA scope found in token' unless waba_scope

    waba_id = waba_scope['target_ids']&.first
    raise 'No WABA ID found in scope' unless waba_id

    # Get business name
    business_response = Faraday.get(
      "https://graph.facebook.com/v21.0/#{waba_id}",
      { access_token: access_token, fields: 'name' }
    )

    business_data = JSON.parse(business_response.body) if business_response.success?
    business_name = business_data&.dig('name') || "WhatsApp Business #{waba_id}"

    { waba_id: waba_id, business_name: business_name }
  end

  def fetch_phone_info(waba_id, access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Fetching phone numbers for WABA #{waba_id}") }

    response = Faraday.get(
      "https://graph.facebook.com/v21.0/#{waba_id}/phone_numbers",
      { access_token: access_token }
    )

    raise "Phone info fetch failed: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    phone_numbers = data['data']

    raise 'No phone numbers found for WABA' if phone_numbers.empty?

    # Use the first verified phone number or fallback to first available
    verified_phone = phone_numbers.find { |phone| phone['code_verification_status'] == 'VERIFIED' }
    phone_data = verified_phone || phone_numbers.first

    {
      phone_number_id: phone_data['id'],
      phone_number: phone_data['display_phone_number'],
      verified: phone_data['code_verification_status'] == 'VERIFIED'
    }
  end

  def create_or_update_channel(waba_info, phone_info, access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info('Creating/updating WhatsApp channel') }

    # Check if channel already exists
    existing_channel = Channel::Whatsapp.find_by(
      account: @account,
      phone_number: phone_info[:phone_number]
    )

    channel_attributes = {
      phone_number: phone_info[:phone_number],
      provider: 'whatsapp_cloud',
      provider_config: {
        api_key: encrypt_token(access_token),
        phone_number_id: phone_info[:phone_number_id],
        business_account_id: waba_info[:waba_id],
        webhook_verify_token: SecureRandom.hex(16)
      }
    }

    if existing_channel
      existing_channel.update!(channel_attributes)
      existing_channel
    else
      Channel::Whatsapp.create!(
        channel_attributes.merge(account: @account)
      )
    end
  end

  def setup_webhooks(waba_id, access_token)
    Rails.logger.tagged('WHATSAPP') { Rails.logger.info("Setting up webhooks for WABA #{waba_id}") }

    webhook_url = webhooks_whatsapp_url(protocol: 'https', host: ENV.fetch('FRONTEND_URL', 'localhost:3000'))

    response = Faraday.post(
      "https://graph.facebook.com/v21.0/#{waba_id}/subscribed_apps",
      {
        access_token: access_token,
        subscribed_fields: 'messages,message_deliveries,messaging_optins,message_echoes'
      }.to_json,
      { 'Content-Type' => 'application/json' }
    )

    Rails.logger.tagged('WHATSAPP') { Rails.logger.warn("Webhook setup failed but continuing: #{response.body}") } unless response.success?

    # Also try to set webhook URL (this might require additional permissions)
    Faraday.post(
      "https://graph.facebook.com/v21.0/#{waba_id}/webhook",
      {
        access_token: access_token,
        callback_url: webhook_url,
        verify_token: SecureRandom.hex(16),
        fields: 'messages,message_deliveries,messaging_optins,message_echoes'
      }.to_json,
      { 'Content-Type' => 'application/json' }
    )
  rescue StandardError => e
    Rails.logger.tagged('WHATSAPP') { Rails.logger.warn("Webhook URL setup failed: #{e.message}") }
    # Don't fail the entire process if webhook setup fails
  end

  def encrypt_token(token)
    # Use Rails encrypted credentials for token storage
    # For now, we'll use a simple approach - in production, implement proper encryption
    token
  end

  def webhooks_whatsapp_url(**options)
    Rails.application.routes.url_helpers.process_payload_webhooks_whatsapp_url(**options)
  end
end
