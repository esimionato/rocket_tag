require 'squeel'

module RocketTag
  module Taggable
    def self.included(base)
      base.extend ClassMethods
    end

    class Manager

      attr_reader :contexts
      attr_writer :contexts
      attr_reader :klass

      def initialize klass
        @klass = klass
        @contexts = []
        setup_relations
      end

      def setup_relations
        klass.has_many :taggings , :dependent => :destroy , :as => :taggable, :class_name => "RocketTag::Tagging"
        klass.has_many :tags     , :source => :tag, :through => :taggings, :class_name => "RocketTag::Tag"
      end


    end

    def tags_for_context context
      tags.where{taggings.context==my{context}}
    end

    def taggings_for_context context
      taggings.where{taggings.context==my{context}}
    end

    def destroy_tags_for_context context
      taggings_for_context(context).delete_all
    end

    module ClassMethods

      def rocket_tag
        @rocket_tag ||= RocketTag::Taggable::Manager.new(self)
      end

      def tagged_with tags_list, options = {}

        on = options.delete :on
        all = options.delete :all

        q = if all
          joins{tags}.
            where{tags.name.in(my{tags_list})}.
            group{~id}.
            having{count(~id)==my{tags_list.length}}
        else
          joins{tags}.where{tags.name.in(my{tags_list})}
        end
       
        if on
          q = q.where{taggings.context == my{on.to_s} }
        end

        q.select{"distinct #{my{table_name}}.*"}

      end

      def attr_taggable *contexts

        if contexts.blank?
          contexts = [:tag]
        end

        rocket_tag.contexts << contexts

        contexts.each do |context|
          class_eval do

            default_scope do
              preload{taggings}.preload{tags}
            end

            has_many "#{context}_taggings".to_sym, 
              :source => :taggable,  
              :as => :taggable,
              :conditions => { :context => context }

            has_many "#{context}_tags".to_sym,
              :source => :tag,
              :through => :taggings,
              :conditions => [ "taggings.context = ?", context ]

            before_save do
              @tag_dirty ||= Set.new

              @tag_dirty.each do |context|
                list = @tag_cache[context.to_s]
                # Destroy all taggings
                destroy_tags_for_context context

                # Find existing tags
                exisiting_tags = Tag.where{name.in(my{list})}
                exisiting_tag_names = exisiting_tags.map &:name

                # Find missing tags
                tags_names_to_create = list - exisiting_tag_names 

                # Create missing tags
                created_tags = tags_names_to_create.map do |tag_name|
                  Tag.create :name => tag_name
                end

                # Recreate taggings
                tags_to_assign = exisiting_tags + created_tags

                tags_to_assign.each do |tag|
                  tagging = Tagging.create :tag => tag, :taggable => self, :context => context, :tagger => nil
                  self.taggings << tagging
                end
              end
              @tag_dirty = Set.new
            end

            define_method "cache_tags" do
              unless @tag_cache
                @tag_cache ||= send("taggings").group_by{|f| f.context }
                @tag_cache.each do |k,v|
                  @tag_cache[k] = v.map{|t|t.tag.name}
                end
              end
              @tag_cache
            end

            # Return an array of RocketTag::Tags for the context
            define_method "#{context}" do
              cache_tags
              if @tag_cache[context.to_s]
                @tag_cache[context.to_s]
              else
                []
              end
            end


            define_method "#{context}=" do |list|

              # Ensure the tags are loaded
              cache_tags

              @tag_cache[context.to_s] = list
              @tag_dirty << context

                
            end
          end
        end
      end

    end

  end
end
