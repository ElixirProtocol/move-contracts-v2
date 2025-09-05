include .env

.PHONY: mint

mint:
	sui client call --package $(PACKAGE_ADDRESS) --module usdc --function mint \
		--args \
			$(USDC_MANAGEMENT_ID) $(to) $(amount)

