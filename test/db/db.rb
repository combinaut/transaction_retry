require 'fileutils'

module TransactionRetry
  module Test
    module Db

      def self.connect_to_database(klass = ::ActiveRecord::Base)
        case ENV['db']
        when 'mysql2'
          connect_to_mysql2(klass)
        when 'postgresql'
          connect_to_postgresql(klass)
        when 'sqlite3'
          connect_to_sqlite3(klass)
        else
          connect_to_mysql2(klass)
        end
      end

      def self.connect_to_mysql2(klass = ::ActiveRecord::Base)
        klass.establish_connection(
          :adapter => "mysql2",
          :database => "transaction_retry_test",
          :user => 'root',
          :password => ''
        )
      end

      def self.connect_to_postgresql(klass = ::ActiveRecord::Base)
        klass.establish_connection(
          :adapter => "postgresql",
          :database => "transaction_retry_test",
          :user => 'qertoip',
          :password => 'test123'
        )
      end

      def self.connect_to_sqlite3(klass = ::ActiveRecord::Base)
        klass.establish_connection(
          :adapter => "sqlite3",
          :database => ":memory:",
          :verbosity => "silent"
        )
      end

    end
  end
end
