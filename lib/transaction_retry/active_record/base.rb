require 'active_record/base'

module TransactionRetry
  module ActiveRecord
    module Base

      def self.included( base )
        base.extend( ClassMethods )
        base.class_eval do
          class << self
            alias_method :transaction_without_retry, :transaction
            alias_method :transaction, :transaction_with_retry
          end
        end
      end

      module ClassMethods

        def transaction_with_retry(*objects, &block)
          tr_increment_nesting_depth
          retry_count = 0

          opts = if objects.last.is_a? Hash
            objects.last
          else
            {}
          end

          retry_on = opts.delete(:retry_on)
          max_retries = opts.delete(:max_retries) || TransactionRetry.max_retries

          begin
            transaction_without_retry(*objects, &block)
          rescue *[::ActiveRecord::TransactionIsolationConflict, *retry_on]
            raise if retry_count >= max_retries
            raise if tr_in_nested_transaction?

            retry_count += 1
            postfix = { 1 => 'st', 2 => 'nd', 3 => 'rd' }[retry_count] || 'th'

            type_s = case $!
            when ::ActiveRecord::TransactionIsolationConflict
              "Transaction isolation conflict"
            else
              $!.class.name
            end

            logger.warn "#{type_s} detected. Retrying for the #{retry_count}-#{postfix} time..." if logger
            tr_exponential_pause( retry_count )
            retry
          ensure
            tr_decrement_nesting_depth
          end
        end

        private

          # Sleep 0, 1, 2, 4, ... seconds up to the TransactionRetry.max_retries.
          # Cap the sleep time at 32 seconds.
          # An ugly tr_ prefix is used to minimize the risk of method clash in the future.
          def tr_exponential_pause( count )
            seconds = TransactionRetry.wait_times[count-1] || 32

            if TransactionRetry.fuzz
              fuzz_factor = [seconds * 0.25, 1].max

              seconds += rand * (fuzz_factor * 2) - fuzz_factor
            end

            sleep( seconds ) if seconds > 0
          end

          # Returns true if we are in the nested transaction (the one with :requires_new => true),
          # or if we're not in a nested transaction on this connection but are being called from within
          # a transaction_with_retry block on another connection that will end up executing this transaction again if it
          # bubbles a TransactionIsolationConflict up after depleting all its retries.
          # e.g. ModelOnConnectionA.transaction { ModelOnConnectionB.transaction { ... } } => # Retry the outer transaction block, not the inner then the outer (and thus the inner again)
          # Returns false otherwise.
          # An ugly tr_ prefix is used to minimize the risk of method clash in the future.
          def tr_in_nested_transaction?
            connection.open_transactions != 0 || tr_nesting_depth > 1
          end

          def tr_increment_nesting_depth
            Thread.current[:tr_nesting_depth] = tr_nesting_depth + 1
          end

          def tr_decrement_nesting_depth
            Thread.current[:tr_nesting_depth] = tr_nesting_depth - 1
          end

          # Returns an integer indicating how deeply nested we are in transaction_with_retry calls.
          def tr_nesting_depth
            Thread.current[:tr_nesting_depth] ||= 0
          end
      end
    end
  end
end

ActiveRecord::Base.send( :include, TransactionRetry::ActiveRecord::Base )
