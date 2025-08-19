include .env

.PHONY: initialize-minting add-role remove-role has-role add-supported-asset deposit-to-locked-funds

initialize-minting:
	sui client call --package $(PACKAGE_ADDRESS) --module deusd_minting --function initialize \
		--args \
			$(ADMIN_CAP_ID) $(DEUSD_MINTING_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) $(PACKAGE_ADDRESS) \
			$(CUSTODIANS) \
			$(max_mint_per_second) $(max_redeem_per_second)

add-custodian:
	sui client call --package $(PACKAGE_ADDRESS) --module deusd_minting --function add_custodian_address\
		--args \
			$(ADMIN_CAP_ID) $(DEUSD_MINTING_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) \
			$(address) \

add-role:
	sui client call --package $(PACKAGE_ADDRESS) --module config --function add_role \
		--args \
			$(ADMIN_CAP_ID) $(GLOBAL_CONFIG_ID) \
			$(address) $(role)

remove-role:
	sui client call --package $(PACKAGE_ADDRESS) --module config --function remove_role \
		--args \
			$(ADMIN_CAP_ID) $(GLOBAL_CONFIG_ID) \
			$(address) $(role)

has-role:
	sui client call --dev-inspect --package $(PACKAGE_ADDRESS) --module config --function has_role \
		--args \
			$(GLOBAL_CONFIG_ID) $(address) $(role)

add-supported-asset:
	sui client call --package $(PACKAGE_ADDRESS) --module deusd_minting --function add_supported_asset \
		--type-args \
			$(COLLATERAL_TYPE) \
		--args \
			$(ADMIN_CAP_ID) $(DEUSD_MINTING_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID)

deposit-to-locked-funds:
	sui client call --package $(PACKAGE_ADDRESS) --module locked_funds --function deposit \
		--type-args \
			$(COLLATERAL_TYPE) \
		--args \
			$(LOCKED_FUNDS_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) $(coins)

