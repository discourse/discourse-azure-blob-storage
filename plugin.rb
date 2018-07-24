# name: discourse-azure-blob-storage
# about: Azure Blob storage
# version: 0.0.1
# authors: Maja
# url: https://github.com/majakomel/discourse-azure-blob-storage

require "file_store/base_store"

# GEMS
gem 'faraday_middleware', '0.11.0', {require: false}
gem 'azure-core', '0.1.13', {require: false}
gem 'azure-storage-common', '1.0.1', {require: false}
gem 'azure-storage-blob', '1.0.1', {require: false}

require 'azure/storage/blob'

enabled_site_setting :azure_blob_storage_enabled

after_initialize do

  SiteSetting::Upload.class_eval do
    class << self
      alias_method :core_s3_cdn_url, :s3_cdn_url
      alias_method :core_enable_s3_uploads, :enable_s3_uploads
      alias_method :core_absolute_base_url, :absolute_base_url
      alias_method :core_s3_base_url, :s3_base_url
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

    def self.s3_base_url
      return "//#{SiteSetting.azure_blob_storage_account_name}.blob.core.windows.net" if SiteSetting.azure_blob_storage_enabled
      core_s3_base_url
    end

    def self.absolute_base_url
      return "//#{SiteSetting.azure_blob_storage_account_name}.blob.core.windows.net" if SiteSetting.azure_blob_storage_enabled
      core_absolute_base_url
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
