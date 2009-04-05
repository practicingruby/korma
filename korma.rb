require 'rubygems'
require 'grit'
require 'redcloth'
require "builder"
require "fileutils"
require "haml"

KORMA_DIR = File.expand_path(File.dirname(__FILE__))

module Korma
  module  Blog

    include FileUtils

    class Entry 
      def initialize(blob, author="")
        entry_data = Blog.parse_entry(blob.data)
        base_path = "posts/#{author}/"

        @filename        = "#{blob.name}.html"
        @author_url      = "http://#{Korma::Blog.domain}/#{base_path}"
        @author          = Blog.author_names[author]
        @title           = entry_data[:title]
        @description     = entry_data[:description]
        @entry           = entry_data[:entry] 
        @published_date  = commit_date(blob, base_path)
        @url             = "http://#{Korma::Blog.domain}/#{base_path}#{@filename}"
      end

      attr_reader :title, :description, :entry, :published_date, :url, :author_url, :author, :filename 

      private

      def commit_date(blob, base_path)
        repo = Korma::Blog.repository
        Grit::Blob.blame(repo, repo.head.commit, "#{base_path}#{blob.name}")[0][0].date
      end

    end

    extend self 
    attr_accessor :repository, :author_names,  :www_dir, :title, :domain, :description

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

    def site_feed
      to_rss(all_entries)
    end

    def entries_for_author(author)
       tree = repository.tree / "posts/#{author}"
       tree.contents.map { |e| Entry.new(e, author)  }
    end

    def feed(author)
      to_rss entries_for_author(author).sort { |a,b| b.published_date <=> a.published_date }     
    end

    def author_index(author)
      @author  = author
      @entries = entries_for_author(author).sort { |a,b| b.published_date <=> a.published_date }
      haml :author_index
    end

    def site_index
      @entries = Korma::Blog.all_entries
      haml :index
    end

    def bio(author)
      node = (Korma::Blog.repository.tree / "about/#{author}")

      "<html><body>#{RedCloth.new(node.data).to_html}</body></html>"
    end

    def update_stylesheet
      if css = repository.tree / "styles.css"
        write "styles.css", css.data
      end
    end

    def layout
      if layout = repository.tree / "layout.haml"
        Haml::Engine.new(layout.data).render(binding)
      else
        yield
      end
    end

    def generate_static_files
      mkdir_p www_dir
      cd www_dir
      write "feed.xml", site_feed
      
      write 'index.html', site_index

      mkdir_p "feed"
      mkdir_p "about"
      authors.each do |author|
        write "feed/#{author}.xml", feed(author)
        mkdir_p "posts/#{author}"
        write "posts/#{author}/index.html", author_index(author)
        entries_for_author(author).each do |e|
          @post = e
          @contents = RedCloth.new(e.entry).to_html
          write "posts/#{author}/#{e.filename}", haml(:post)
        end
        write "about/#{author}.html", bio(author)
        write repository.tree
      end
    end

    def write(file, contents)
      File.open(file, "w") { |f| f << contents }
    end

    def haml(file)
      engine = Haml::Engine.new(File.read("#{KORMA_DIR}/views/#{file}.haml"))
      layout { engine.render(binding) }
    end

    def to_rss(entries)
      xml = Builder::XmlMarkup.new
      xml.instruct!
      xml.rss :version => "2.0" do
        xml.channel do
          xml.title       title
          xml.link        "http://#{domain}/"
          xml.description  description
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

Korma::Blog.repository   = Grit::Repo.new(ARGV[0])
config =  YAML.load((Korma::Blog.repository.tree / "korma_config.yml").data)

Korma::Blog.title  = config['title']
Korma::Blog.domain = config['domain']
Korma::Blog.description = config['description']
Korma::Blog.author_names = config['authors']
Korma::Blog.www_dir  = ARGV[1] || "www"
Korma::Blog.generate_static_files
