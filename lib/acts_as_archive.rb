# ActsAsArchive
require 'active_record'


module Digi
  module Acts
    module Archive

      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end
      
      module ClassMethods
        def acts_as_archive
          extend Digi::Acts::Archive::ArchiveMethods
          include Digi::Acts::Archive::InstanceMethods
          
          const_set(archive_class_name, Class.new(ActiveRecord::Base)).class_eval do
            
          end
        end
      end

      module InstanceMethods
        
        def archive_class
          const_get archive_class_name
        end
        
        def archive_class_name
          "Archive"
        end
        
        def archived_columns
          self.class.columns.select{|c| c.name != "id"}
        end
        
        def create_archive_table
            
            self.connection.create_table(archive_table_name) do |t|
              t.column :archived_on, :timestamp
              t.column :unarchived_id, :integer
            end
            
            self.archived_columns.each do |col|
            puts "***** column #{col.name}"
            self.connection.add_column archive_table_name, col.name, col.type, 
              :limit => col.limit, 
              :default => col.default,
              :scale => col.scale,
              :precision => col.precision
            end
        end
        
        def drop_archive_table
          self.connection.drop_table archive_table_name
        end
        
        def archive_table_name
          "#{base_class.name.demodulize.underscore}_archives"
        end
        
        def archive
          digi_archive = self.class.archive_class
          arch = digi_archive.new
          self.clone_archive_model(self, arch)
          Post.transaction do
            arch.save
            self.destroy
          end
          return arch
        end
        
        def clone_archive_model_reverse(orig_model, new_model)
          self.archived_columns.each do |key|
            orig_model.send("#{key.name}=", new_model.send(key.name)) if new_model.has_attribute?(key.name)
          end
          orig_model.id = new_model.unarchived_id
        end
        
        def clone_archive_model(orig_model, new_model)
          self.archived_columns.each do |key|
            new_model.send("#{key.name}=", orig_model.send(key.name)) if orig_model.has_attribute?(key.name)
          end
          new_model.unarchived_id = orig_model.id
          new_model.archived_on = Time.now
        end
      end

      # add your class methods here
      module ArchiveMethods
        
        
        def archive_table_name
          "#{base_class.name.demodulize.underscore}_archives"
        end
        
        def archive_class
          const_get archive_class_name
        end
        
        def archive_class_name
          "Archive"
        end
        
        def archived_columns
          self.columns.select{|c| c.name != "id"}
        end
        
        
        def unarchive(oldid)
          digi_archive = Post.archive_class
          arch = digi_archive.find_by_unarchived_id(oldid)
          arch = arch.first if arch.is_a?(Array)
          post = Post.new
          post.clone_archive_model_reverse(post, arch)
          Post.transaction do
            arch.destroy
            post.save
          end
          return post
        end
        
        # def archive
        #   digi_archive = self.class.archive_class
        #   arch = digi_archive.new
        #   self.clone_archive_model(self, arch)
        #   arch.save
        #   self.delete
        #   return arch
        # end
        # 
        # def unarchive
        #   
        # end
        
        def find_archive(*args)
          
          options = args.extract_options!
          conditions = options[:conditions]
          order = options[:order] ? "ORDER BY #{options[:order]}" : ""
          limit = options[:limit] ? "LIMIT #{options[:limit]}" : ""
          offset = options[:offset] ? "OFFSET #{options[:offset]}" : ""
          
          where1 = "WHERE #{conditions.is_a?(Array) ? conditions.first : conditions}"
          where2 = archive_change_ids_to_unarchived_id(where1)
          
          
          if args.first == :first
            limit = "LIMIT 1"
          elsif args.first == :all
            nil
          else
            where1 = "WHERE (#{args.map{|a| "id=#{a}"}.join(" or ")}) AND (#{conditions.is_a?(Array) ? conditions.first : conditions})"
            where2 = archive_change_ids_to_unarchived_id(where1)
          end
          
          puts "***WHERE*** \"#{where1}\""
          
          if where1 == "WHERE " or where1 == "WHERE () AND ()"
            where1 = ""
            where2 = ""
          end
          
          where1.gsub!(/AND \(\)/,"")
          where2.gsub!(/AND \(\)/,"")
          
          sql1columns = self.archived_columns
          sql1columns = sql1columns.map{|c| c.name}
          sql1 = "(SELECT id, #{sql1columns.join(",")} FROM #{self.table_name} #{where1})"
          sql2 = "(SELECT unarchived_id as id, #{sql1columns.join(",")} FROM #{archive_table_name} #{where2})"
          
          puts "***SQL***  #{sql1} UNION #{sql2} #{order} #{limit} #{offset}"
          # 
          # if conditions.is_a?(Array)
          #   results = self.find_by_sql("#{sql1} UNION #{sql2} #{order} #{limit} #{offset}", conditions[1..conditions.length], conditions[1..conditions.length])
          # else
            results = self.find_by_sql("#{sql1} UNION #{sql2} #{order} #{limit} #{offset}")
          # end
          
          if args.first == :first || args.length==0
            return results[0]
          else
            return results
          end
            
          # options = args.extract_options!
          # 
          # results = case args.first
          #   when :first then []
          #   when :all   then self.find_every(options)
          #   else             self.find_from_ids(args, options)
          # end
          # results = self.find(*args)
          # if options.is_a?(Array)
          #   options.first = archive_change_ids_to_unarchived_id(options.first)
          # else
          #   options = archive_change_ids_to_unarchived_id(options)
          # end
          # archived_results = case args.first
          #   when :first then self.class.archive_class.find_initial(options)
          #   when :all   then self.class.archive_class.find_every(options)
          #   else do
          #     if options.is_a?(Array)
          #       options.first = "(#{args.map{|a| "unarchived_id = #{a}"}.join(" or ")}) and (#{options.first})"
          #     else
          #       options = "(#{args.map{|a| "unarchived_id = #{a}"}.join(" or ")}) and (#{options})"
          #     end
          #     self.class.archive_class.find_from_ids(:all, options)
          #   end
          # end
          # 
          
        end
        
        def archive_change_ids_to_unarchived_id(optionstr)
          optionstr = optionstr.gsub(/( id=| id =|^id=|^id =)/," unarchived_id=")
          optionstr = optionstr.gsub(/(,id=|,id =)/,", unarchived_id=")
          optionstr = optionstr.gsub(/(\(id=|\(id =)/,"(unarchived_id=")
          
        end
      end
    
  
    end
  end
end



ActiveRecord::Base.send :include, Digi::Acts::Archive
