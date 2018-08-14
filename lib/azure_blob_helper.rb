class AzureBlobHelper

  def initialize(options = {})
    @azure_options = default_azure_options.merge(options)
  end

  def upload(path, file, options = {})
    blob_service.create_block_blob(azure_blob_container, path, file, options)
  end

  def move_to_tombstone(source_blob_name)
    # copy the file in tombstone
    blob_service.copy_blob(
            azure_blob_container,
            "/tombstone/#{path}",
            azure_blob_container,
            source_blob_name)
    # delete the file
    blob_service.delete_blob(azure_blob_container, source_blob_name)
  end

  def tombstone_cleanup(grace_period)
    blob_list = blob_service.list_blobs(azure_blob_container, {prefix: "tombstone"})
    blob_list.each do |blob|
      last_modified_diff = ((Time.now.utc - Time.parse(blob.properties[:last_modified])) / 1.day).round
      blob_service.delete_blob(azure_blob_container, blob.name) if last_modified_diff > grace_period
    end
  end

  def ensure_cors!
    rule = nil

    begin
      rule = blob_service.get_service_properties.cors.cors_rules
    rescue Azure::Core::Http::HTTPError => ex
      puts "Status: #{ex.status_code}, Description: #{ex.description}"
      puts "Exception: #{ex}"
    end

    cors_rule = Azure::Storage::Common::Service::CorsRule.new
    cors_rule.allowed_origins = ["*"]
    cors_rule.allowed_methods = %w(HEAD GET)
    cors_rule.allowed_headers = ["Authorization"]
    cors_rule.max_age_in_seconds = 3000

    service_properties = Azure::Storage::Common::Service::StorageServiceProperties.new
    service_properties.cors.cors_rules = [cors_rule]

    unless rule.any?
      puts "installing CORS rule"

      blob_service.set_service_properties(service_properties)
    end
  end

  def azure_blob_container
    GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_container_name : SiteSetting.azure_blob_storage_container_name
  end

  private

  def blob_service
    @blob_service ||= Azure::Storage::Blob::BlobService.create(@azure_options)
  end

  def azure_blob_account_name
    GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_account_name : SiteSetting.azure_blob_storage_account_name
  end

  def azure_blob_access_key
    GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_access_key : SiteSetting.azure_blob_storage_access_key
  end

  def azure_blob_sas_token
    GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_sas_token : SiteSetting.azure_blob_storage_sas_token
  end

  def default_azure_options
    opts = { storage_account_name: azure_blob_account_name }

    if azure_blob_sas_token.present?
      opts[:storage_sas_token] = azure_blob_sas_token
    elsif azure_blob_access_key.present?
      opts[:storage_access_key] = azure_blob_access_key
    end

    opts
  end

end
