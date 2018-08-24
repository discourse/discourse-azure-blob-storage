# name: discourse-azure-blob-storage
# about: Azure Blob Storage
# version: 0.0.2
# authors: Maja Komel
# url: https://github.com/discourse/discourse-azure-blob-storage

require "file_store/base_store"

# GEMS
gem 'faraday_middleware', '0.11.0', {require: false}
gem 'azure-core', '0.1.13', {require: false}
gem 'azure-storage-common', '1.0.1', {require: false}
gem 'azure-storage-blob', '1.0.1', {require: false}

require 'azure/storage/blob'

enabled_site_setting :azure_blob_storage_enabled

after_initialize do
  require File.expand_path("../lib/azure_blob_helper.rb", __FILE__)
  require File.expand_path("../jobs/scheduled/check_azure_sas_token.rb", __FILE__)

  module SiteSettingUploadExtension
    def s3_cdn_url
      if  GlobalSetting.use_azure_with_cdn?
        return GlobalSetting.azure_blob_storage_cdn_url
      elsif SiteSetting.azure_blob_storage_enabled
        return SiteSetting.azure_blob_storage_cdn_url
      end

      super
    end

    def azure_helper
      @azure_helper ||= AzureBlobHelper.new
    end

    def enable_s3_uploads
      if SiteSetting.azure_blob_storage_enabled || GlobalSetting.use_azure?
        azure_helper
        return true
      else
        super
      end
    end

    def s3_base_url
      if GlobalSetting.use_azure?
        return "//#{GlobalSetting.azure_blob_storage_account_name}.blob.core.windows.net/#{azure_helper.azure_blob_container}"
      elsif SiteSetting.azure_blob_storage_enabled
        return "//#{SiteSetting.azure_blob_storage_account_name}.blob.core.windows.net/#{azure_helper.azure_blob_container}"
      end

      super
    end

    def absolute_base_url
      if GlobalSetting.use_azure?
        return "//#{GlobalSetting.azure_blob_storage_account_name}.blob.core.windows.net/#{azure_helper.azure_blob_container}"
      elsif SiteSetting.azure_blob_storage_enabled
        return "//#{SiteSetting.azure_blob_storage_account_name}.blob.core.windows.net/#{azure_helper.azure_blob_container}"
      end

      super
    end
  end

  class ::SiteSetting::Upload
    singleton_class.prepend SiteSettingUploadExtension
  end

  module DiscourseExtension
    def store
      if SiteSetting.azure_blob_storage_enabled || GlobalSetting.use_azure?
        @azure_blob_loaded ||= require File.expand_path("../lib/azure_blob_store.rb", __FILE__)
        FileStore::AzureStore.new
      else
        super
      end
    end
  end

  ::Discourse.module_eval do
    singleton_class.prepend DiscourseExtension
  end

  ApplicationHelper.module_eval do
    alias_method :core_preload_script, :preload_script

    def preload_script(script)
      if GlobalSetting.use_azure_with_cdn?
        path = asset_path("#{script}.js")

        if GlobalSetting.azure_blob_storage_cdn_url
          if GlobalSetting.cdn_url
            path = path.gsub(GlobalSetting.cdn_url, GlobalSetting.azure_blob_storage_cdn_url)
          else
            path = "#{GlobalSetting.azure_blob_storage_cdn_url}#{path}"
          end

          if is_brotli_req?
            path = path.gsub(/\.([^.]+)$/, '.br.\1')
          end

        elsif GlobalSetting.cdn_url&.start_with?("https") && is_brotli_req?
          path = path.gsub("#{GlobalSetting.cdn_url}/assets/", "#{GlobalSetting.cdn_url}/brotli_asset/")
        end

        return "<link rel='preload' href='#{path}' as='script'/><script src='#{path}'></script>".html_safe
      end

      core_preload_script(script)
    end
  end

  GlobalSetting.class_eval do
    def self.use_azure?
      # avoid errors in when no azure related GlobalSettings defined
      if !defined?(azure_blob_storage_account_name) &&
        !defined?(azure_blob_storage_container_name) &&
        (!defined?(azure_blob_storage_sas_token) ||
        !defined?(azure_blob_storage_access_key))
        return false
      else
        (@use_azure ||=
          begin
            azure_blob_storage_account_name &&
            azure_blob_storage_container_name && (
              azure_blob_storage_sas_token || azure_blob_storage_access_key
            ) ? :true : :false
          end) == :true
      end
    end

    def self.use_azure_with_cdn?
      return false if !defined?(azure_blob_storage_cdn_url)
      @use_azure_with_cdn ||= azure_blob_storage_cdn_url ? true : false
    end
  end
end
