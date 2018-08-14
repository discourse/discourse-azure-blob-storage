require './plugins/discourse-azure-blob-storage/lib/azure_blob_helper'

module FileStore

  class AzureStore < ::FileStore::BaseStore

    def initialize(azure_helper = nil)
      @azure_helper = azure_helper || AzureBlobHelper.new
    end

    def store_upload(file, upload, content_type = nil)
      path = get_path_for_upload(upload)
      store_file(file, path, content_type: content_type, filename: upload.original_filename, cache_locally: true)
    end

    def store_optimized_image(file, optimized_image, content_type = nil)
      path = get_path_for_optimized_image(optimized_image)
      store_file(file, path, content_type: content_type)
    end

    def store_file(file, path, opts = {})
      filename = opts[:filename].presence || File.basename(path)
      cache_file(file, File.basename(path)) if opts[:cache_locally]
      options = {
        content_type: opts[:content_type].presence || MiniMime.lookup_by_filename(filename)&.content_type
      }
      options[:content_disposition] = "attachment; filename*=UTF-8''#{URI.encode(filename)}" unless FileHelper.is_image?(filename)
      @azure_helper.upload(path, file, options)

      "#{absolute_base_url}/#{path}"
    end

    def remove_file(url, path)
      return unless has_been_uploaded?(url)
      @azure_helper.move_to_tombstone(path)
    end

    def has_been_uploaded?(url)
      return false if url.blank?
      base_hostname = URI.parse(absolute_base_url).hostname
      return true if url[base_hostname]

      return false if azure_blob_storage_cdn_url.blank?
      cdn_hostname = URI.parse(azure_blob_storage_cdn_url || "").hostname
      cdn_hostname.presence && url[cdn_hostname]
    end

    def azure_blob_container
      GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_container_name : SiteSetting.azure_blob_storage_container_name
    end

    def absolute_base_url
      @absolute_base_url ||= SiteSetting.Upload.absolute_base_url
    end

    def purge_tombstone(grace_period)
      @azure_helper.tombstone_cleanup(grace_period)
    end

    def path_for(upload)
      url = upload.try(:url)
      FileStore::LocalStore.new.path_for(upload) if url && url[/^\/[^\/]/]
    end

    def azure_blob_storage_cdn_url
      GlobalSetting.use_azure? ? GlobalSetting.azure_blob_storage_cdn_url : SiteSetting.azure_blob_storage_cdn_url
    end

    def cdn_url(url)
      return url if azure_blob_storage_cdn_url.blank?
      schema = url[/^(https?:)?\/\//, 1]
      url.sub("#{schema}#{absolute_base_url}", azure_blob_storage_cdn_url)
    end

    def external?
      true
    end

  end
end
