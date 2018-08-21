module Jobs

  class CheckAzureSasToken < ::Jobs::Scheduled
    WARN_ON_DAYS_BEFORE_EXPIRY = [30, 20, 10, 3, 2, 1]

    every 1.day

    def execute(args = nil)
      sas_token_params = Rack::Utils.parse_nested_query(GlobalSetting.azure_blob_storage_sas_token)

      # Warning is sent if expiry is set on 'ad-hoc' SAS token, there is another
      # way to create the token - with stored access policy, but in this case
      # it's not possible to access expiry date without storage access key :/
      if sas_token_params.has_key?("se")
        expiry_date = sas_token_params["se"].to_date

        send_warning(expiry_date)
      end
    end

    def send_warning(expiry_date)
      today = Time.now.utc.to_date
      days_left = (expiry_date - today).to_i

      if WARN_ON_DAYS_BEFORE_EXPIRY.include?(days_left)
        PostCreator.create(
          Discourse.system_user,
          target_group_names: Group[:admins].name,
          archetype: Archetype.private_message,
          subtype: TopicSubtype.system_message,
          title: I18n.t('azure_blob_storage.system_warning.title', days_left: days_left),
          raw: I18n.t('azure_blob_storage.system_warning.raw', days_left: days_left)
        )
      end
    end

  end
end
