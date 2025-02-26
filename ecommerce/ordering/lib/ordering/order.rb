module Ordering
  class Order
    include AggregateRoot

    AlreadySubmitted = Class.new(StandardError)
    AlreadyConfirmed = Class.new(StandardError)
    NotSubmitted = Class.new(StandardError)
    OrderHasExpired = Class.new(StandardError)
    CannotRemoveZeroQuantityItem = Class.new(StandardError)

    def initialize(id)
      @id = id
      @state = :draft
      @basket = Basket.new
    end

    def submit(order_number)
      raise AlreadySubmitted if @state.equal?(:submitted)
      raise OrderHasExpired if @state.equal?(:expired)
      apply OrderSubmitted.new(
        data: {
          order_id: @id,
          order_number: order_number,
          order_lines: @basket.order_lines
        }
      )
    end

    def confirm
      raise OrderHasExpired if @state.equal?(:expired)
      raise NotSubmitted unless @state.equal?(:submitted)
      apply OrderConfirmed.new(data: { order_id: @id })
    end

    def expire
      raise AlreadyConfirmed if @state.equal?(:confirmed)
      apply OrderExpired.new(data: { order_id: @id })
    end

    def add_item(product_id)
      raise AlreadySubmitted unless @state.equal?(:draft)
      apply ItemAddedToBasket.new(
        data: {
          order_id: @id,
          product_id: product_id,
          quantity_before: @basket.quantity(product_id)
        }
      )
    end

    def remove_item(product_id)
      raise AlreadySubmitted unless @state.equal?(:draft)
      raise CannotRemoveZeroQuantityItem if @basket.quantity(product_id).zero?
      apply ItemRemovedFromBasket.new(data: { order_id: @id, product_id: product_id })
    end

    def cancel
      raise OrderHasExpired if @state.equal?(:expired)
      raise NotSubmitted unless @state.equal?(:submitted)
      apply OrderCancelled.new(data: { order_id: @id })
    end

    on OrderSubmitted do |event|
      @customer_id = event.data[:customer_id]
      @number = event.data[:order_number]
      @state = :submitted
    end

    on OrderConfirmed do |event|
      @state = :confirmed
    end

    on OrderExpired do |event|
      @state = :expired
    end

    on OrderCancelled do |event|
      @state = :cancelled
    end

    on ItemAddedToBasket do |event|
      @basket.increase_quantity(event.data[:product_id])
    end

    on ItemRemovedFromBasket do |event|
      @basket.decrease_quantity(event.data[:product_id])
    end

    class Basket
      def initialize
        @order_lines = Hash.new(0)
      end

      def increase_quantity(product_id)
        order_lines[product_id] = quantity(product_id) + 1
      end

      def decrease_quantity(product_id)
        order_lines[product_id] -= 1
        order_lines.delete(product_id) if order_lines.fetch(product_id).equal?(0)
      end

      def order_lines
        @order_lines
      end

      def quantity(product_id)
        order_lines[product_id]
      end
    end
  end
end
