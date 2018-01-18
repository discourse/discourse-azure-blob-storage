# name: discourse-azure-blob-storage
# about: Azure Blob storage
# version: 0.0.1
# authors: Maja

require "file_store/base_store"

# GEMS
gem 'faraday_middleware', '0.11.0', {require: false}
gem 'azure-core', '0.1.14', {require: false}
gem 'azure-storage', '0.15.0.preview', {require: false}
gem 'systemu', '2.6.5', {require: false}
gem 'azure', '0.7.10'

enabled_site_setting :azure_blob_storage_enabled

after_initialize do

  SiteSetting::Upload.class_eval do
    class << self
      alias_method :core_s3_cdn_url, :s3_cdn_url
      alias_method :core_enable_s3_uploads, :enable_s3_uploads
    end

    def self.s3_cdn_url
      if SiteSetting.azure_blob_storage_enabled
        SiteSetting.azure_cdn_url
      else
        core_s3_cdn_url
      end
    end

    def self.enable_s3_uploads
      return true if SiteSetting.azure_blob_storage_enabled
      core_enable_s3_uploads
    end
  end

  Discourse.module_eval do
    class << self
      alias_method :core_store, :store
    end
    def self.store
      if SiteSetting.azure_blob_storage_enabled
        @azure_blob_loaded ||= require './plugins/discourse-azure-blob-storage/lib/azure_blob_store'
        FileStore::AzureStore.new
      else
        core_store
      end
    end
  end

end
