require_relative "test_helper"

require "timecop"

module Pricing
  class TimePromotionTest < Test
    cover "Pricing::TimePromotion*"

    def test_creates_time_promotion
      uid = SecureRandom.uuid
      data = {
        time_promotion_id: uid
      }

      run_command = -> { create_time_promotion(**data) }

      stream = "Pricing::TimePromotion$#{uid}"
      event = TimePromotionCreated.new(data: data)

      assert_events(stream, event) do
        run_command.call
      end
    end

    def test_labels_time_promotion
      uid = SecureRandom.uuid
      initial_data = {
        time_promotion_id: uid
      }
      create_time_promotion(**initial_data)
      data = {
        time_promotion_id: uid,
        label: "Last Minute"
      }

      run_command = -> { run_command(LabelTimePromotion.new(**data)) }

      stream = "Pricing::TimePromotion$#{uid}"
      event = TimePromotionLabeled.new(data: data)

      assert_events(stream, event) do
        run_command.call
      end
    end

    def test_sets_discount_for_time_promotion
      uid = SecureRandom.uuid
      initial_data = {
        time_promotion_id: uid
      }
      create_time_promotion(**initial_data)
      data = { time_promotion_id: uid, discount: 25 }

      run_command = -> { run_command(SetTimePromotionDiscount.new(**data)) }

      stream = "Pricing::TimePromotion$#{uid}"
      event = TimePromotionDiscountSet.new(data: data)

      assert_events(stream, event) do
        run_command.call
      end
    end

    def test_sets_range_for_time_promotion
      uid = SecureRandom.uuid
      initial_data = {
        time_promotion_id: uid
      }
      create_time_promotion(**initial_data)
      data = {
        time_promotion_id: uid,
        start_time: DateTime.new(2022, 7, 1, 12, 15, 0),
        end_time: DateTime.new(2022, 7, 4, 14, 30, 30)
      }

      run_command = -> { run_command(SetTimePromotionRange.new(**data)) }

      stream = "Pricing::TimePromotion$#{uid}"
      event = TimePromotionRangeSet.new(data: data)

      assert_events(stream, event) do
        run_command.call
      end
    end

    private

    def create_time_promotion(**kwargs)
      run_command(CreateTimePromotion.new(kwargs))
    end
  end

  class DiscountWithTimePromotionTest < Test
    cover "Pricing*"

    def test_calculates_total_value_with_time_promotion
      timestamp = DateTime.new(2022, 5, 30, 15, 33)

      Timecop.freeze(timestamp) do
        product_1_id = SecureRandom.uuid
        set_price(product_1_id, 20)
        order_id = SecureRandom.uuid
        add_item(order_id, product_1_id)
        stream = "Pricing::Order$#{order_id}"

        assert_events(
          stream,
          OrderTotalValueCalculated.new(
            data: {
              order_id: order_id,
              discounted_amount: 20,
              total_amount: 20
            }
          )
        ) { calculate_total_value(order_id) }

        # Current promotions
        first_time_promotion_id = SecureRandom.uuid
        start_time = timestamp - 1
        end_time = timestamp + 1
        set_time_promotion_range(first_time_promotion_id, start_time, end_time)
        set_time_promotion_discount(first_time_promotion_id, 49)

        time_promotion_id = SecureRandom.uuid
        start_time = timestamp
        end_time = timestamp + 1
        set_time_promotion_range(time_promotion_id, start_time, end_time)
        set_time_promotion_discount(time_promotion_id, 1)

        # Not applicable promotions
        time_promotion_id = SecureRandom.uuid
        start_time = timestamp - 2
        end_time = timestamp - 1
        set_time_promotion_range(time_promotion_id, start_time, end_time)
        set_time_promotion_discount(time_promotion_id, 10)

        time_promotion_id = SecureRandom.uuid
        start_time = timestamp + 1
        end_time = timestamp + 2
        set_time_promotion_range(time_promotion_id, start_time, end_time)
        set_time_promotion_discount(time_promotion_id, 15)

        time_promotion_id = SecureRandom.uuid
        start_time = timestamp - 1
        end_time = timestamp
        set_time_promotion_range(time_promotion_id, start_time, end_time)
        set_time_promotion_discount(time_promotion_id, 15)

        assert_events(
          stream,
          OrderTotalValueCalculated.new(
            data: {
              order_id: order_id,
              total_amount: 20,
              discounted_amount: 10,
            }
          )
        ) { calculate_total_value(order_id) }
      end
    end

    def test_calculates_sub_amounts_with_combined_discounts
      timestamp = DateTime.new(2022, 5, 30, 15, 33)

      product_1_id = SecureRandom.uuid
      product_2_id = SecureRandom.uuid
      set_price(product_1_id, 20)
      set_price(product_2_id, 30)
      order_id = SecureRandom.uuid
      stream = "Pricing::Order$#{order_id}"

      assert_events(stream) { calculate_sub_amounts(order_id) }

      add_item(order_id, product_1_id)
      add_item(order_id, product_2_id)
      add_item(order_id, product_2_id)
      assert_events(
        stream,
        PriceItemValueCalculated.new(
          data: {
            order_id: order_id,
            product_id: product_1_id,
            quantity: 1,
            amount: 20,
            discounted_amount: 20
          }
        ),
        PriceItemValueCalculated.new(
          data: {
            order_id: order_id,
            product_id: product_2_id,
            quantity: 2,
            amount: 60,
            discounted_amount: 60
          }
        )
      ) { calculate_sub_amounts(order_id) }
      run_command(
        Pricing::SetPercentageDiscount.new(order_id: order_id, amount: 10)
      )

      first_time_promotion_id = SecureRandom.uuid
      start_time = timestamp - 1
      end_time = timestamp + 1
      set_time_promotion_range(first_time_promotion_id, start_time, end_time)
      set_time_promotion_discount(first_time_promotion_id, 50)

      Timecop.freeze(timestamp) do
        assert_events(
          stream,
          PriceItemValueCalculated.new(
            data: {
              order_id: order_id,
              product_id: product_1_id,
              quantity: 1,
              amount: 20,
              discounted_amount: 8
            }
          ),
          PriceItemValueCalculated.new(
            data: {
              order_id: order_id,
              product_id: product_2_id,
              quantity: 2,
              amount: 60,
              discounted_amount: 24
            }
          )
        ) { calculate_sub_amounts(order_id) }
      end
    end

    def test_takes_last_values_for_time_promotion
      timestamp = DateTime.new(2022, 5, 30, 15, 33)
      time_promotion_id = SecureRandom.uuid
      start_time = timestamp - 5
      end_time = timestamp - 2
      set_time_promotion_range(time_promotion_id, start_time, end_time)
      set_time_promotion_discount(time_promotion_id, 30)

      start_time = timestamp - 1
      end_time = timestamp + 1
      set_time_promotion_range(time_promotion_id, start_time, end_time)
      set_time_promotion_discount(time_promotion_id, 20)
      set_time_promotion_discount(time_promotion_id, 40)

      Timecop.freeze(timestamp) do
        product_1_id = SecureRandom.uuid
        set_price(product_1_id, 20)
        order_id = SecureRandom.uuid
        add_item(order_id, product_1_id)
        stream = "Pricing::Order$#{order_id}"

        assert_events(
          stream,
          OrderTotalValueCalculated.new(
            data: {
              order_id: order_id,
              discounted_amount: 12,
              total_amount: 20
            }
          )
        ) { calculate_total_value(order_id) }
      end
    end

    private

    def set_time_promotion_range(time_promotion_id, start_time, end_time)
      run_command(
        SetTimePromotionRange.new(time_promotion_id: time_promotion_id, start_time: start_time, end_time: end_time)
      )
    end

    def set_time_promotion_discount(time_promotion_id, discount)
      run_command(
        SetTimePromotionDiscount.new(time_promotion_id: time_promotion_id, discount: discount)
      )
    end

    def calculate_sub_amounts(order_id)
      run_command(CalculateSubAmounts.new(order_id: order_id))
    end
  end
end
