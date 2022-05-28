module Pricing
  module Helpers
    class HappyHoursForProduct
      def initialize(event_store)
        @event_store = event_store
      end

      def discount_for(product_id, hour)
        events = @event_store.read.stream("Pricing::Product$#{product_id}").of_type(ProductAddedToHappyHour).to_a

        product = Product.new(product_id)

        product.apply(*events)

        product.happy_hours_schedule.schedule.fetch(hour, 0)
      end
    end
  end
end