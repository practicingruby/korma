require 'rubygems'
require 'sinatra'
require 'grit'
require 'redcloth'
require "builder"

module Korma
  module  Blog

    TITLE  = "Ruby Best Practices"
    DOMAIN = "localhost:4567"
    DESCRIPTION = "Not really implemented yet"
    AUTHORS = { "gregory" => "Gregory Brown",
                "chenoa"  => "Chenoa Siegenthaler" }

    class Entry 
      def initialize(blob, author="")
        entry_data = Blog.parse_entry(blob.data)
        base_path = "posts/#{author}/"

        @author_url      = "http://#{DOMAIN}/#{base_path}"
        @author          = AUTHORS[author]
        @title           = entry_data[:title]
        @description     = entry_data[:description]
        @entry           = entry_data[:entry] 
        @published_date  = commit_date(blob, base_path)
        @url             = "http://#{DOMAIN}/#{base_path}#{blob.name}"
      end

      attr_reader :title, :description, :entry, :published_date, :url, :author_url, :author

      private

      def commit_date(blob, base_path)
        repo = Korma::Blog.repository
        Grit::Blob.blame(repo, repo.head.commit, "#{base_path}#{blob.name}")[0][0].date
      end

    end

    extend self 
    attr_accessor :repository

    def normalize_path(path)
      path.gsub(%r{/+},"/")
    end
    
    def parse_entry(entry)
      entry =~ /=title(.*)=description(.*)=entry(.*)/m   
      { :title => $1.strip, :description => $2.strip, :entry => $3.strip }
    end

    def authors
      (repository.tree / "posts/").contents.map { |e| e.name }  
    end

    def all_entries
      entries = []
      authors.each do |a|
        entries += entries_for_author(a)
      end
      entries.sort { |a,b| b.published_date <=> a.published_date }
    end

    def build_site_feed
      to_rss(all_entries)
    end

    def entries_for_author(author)
       tree = repository.tree / "posts/#{author}"
       tree.contents.map { |e| Entry.new(e, author)  }
    end

    def build_feed(author)
      to_rss entries_for_author(author).sort { |a,b| b.published_date <=> a.published_date }     
    end

    def build_site_index
      all_entries.inject("") do |s,e|
        s + "<p><a href='#{e.url}'>#{e.title}</a>: #{e.description} (<a href='#{e.author_url}'>#{e.author}</a>)"
      end
    end

    def build_index(author)
      entries_for_author(author).inject("<h2>Posts By <a href='/about/#{author}'>#{AUTHORS[author]}</a></h2>") do |s,e|
        s + "<p><a href='#{e.url}'>#{e.title}</a>: #{e.description}"
      end
    end

    def to_rss(entries)
      xml = Builder::XmlMarkup.new
      xml.instruct!
      xml.rss :version => "2.0" do
        xml.channel do
          xml.title       TITLE
          xml.link        "http://#{DOMAIN}/"
          xml.description  DESCRIPTION
          xml.language    "en-us"

          entries.each do |entry|
            xml.item do
              xml.title       entry.title
              xml.description entry.description
              xml.author      "#{entry.author} via rubybestpractices.com"
              xml.pubDate     entry.published_date
              xml.link        entry.url
              xml.guid        entry.url
            end
          end
        end
      end
    end 

  end
end

get %r{^/feed/(.+).xml} do |author|
  Korma::Blog.build_feed(author)
end

get "/feed.xml" do
  Korma::Blog.build_site_feed
end

get "/" do
  Korma::Blog.build_site_index
end

get %r{^/posts/?$} do
  Korma::Blog.build_site_index
end

get %r{^/(posts/.+)} do |path|
  node = (Korma::Blog.repository.tree / path)
  if Grit::Tree === node
    Korma::Blog.build_index(path.sub("posts/","").delete("/"))
  else
    RedCloth.new(Korma::Blog.parse_entry(node.data)[:entry]).to_html
  end
end

get %r{^/(about/.*)} do |author|
  node = (Korma::Blog.repository.tree / author)
  RedCloth.new(node.data).to_html
end

configure do
  Korma::Blog.repository = Grit::Repo.new(ARGV[0])
end
