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
    def self.s3_cdn_url
      SiteSetting.azure_cdn_url
    end

    def self.enable_s3_uploads
      true
    end
  end

  Discourse.module_eval do
    def self.store
      @azure_blob_loaded ||= require './plugins/discourse-azure-blob-storage/lib/azure_blob_store'
      FileStore::AzureStore.new
    end
  end

end
