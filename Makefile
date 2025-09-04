include .env

.PHONY: clean initialize-minting initialize-wdeusd-vault add-role remove-role add-supported-asset remove-supported-asset

clean:
	rm -rf build/

initialize-minting:
	sui client call --package $(PACKAGE_ADDRESS) --module deusd_minting --function initialize \
		--args \
			$(ADMIN_CAP_ID) $(DEUSD_MINTING_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) $(PACKAGE_ADDRESS) \
			$(CUSTODIANS) \
			$(max_mint_per_second) $(max_redeem_per_second)

initialize-wdeusd-vault:
	sui client call --package $(PACKAGE_ADDRESS) --module wdeusd_vault --function initialize \
		--type-args \
			$(WDEUSD_TYPE) \
        --args \
            $(ADMIN_CAP_ID) $(WDEUSD_COIN_METADATA_ID)

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

add-supported-asset:
	sui client call --package $(PACKAGE_ADDRESS) --module deusd_minting --function remove_supported_asset \
		--type-args \
			$(asset_type) \
		--args \
			$(ADMIN_CAP_ID) $(DEUSD_MINTING_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID)

set-operator:
	sui client call --package $(PACKAGE_ADDRESS) --module staking_rewards_distributor --function set_operator \
		--args \
			$(ADMIN_CAP_ID) $(STAKING_REWARDS_DISTRIBUTOR_ID) $(GLOBAL_CONFIG_ID) $(operator)
