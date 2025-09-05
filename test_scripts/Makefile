include .env

.PHONY: initialize-minting initialize-wdeusd-vault add-role remove-role has-role add-supported-asset deposit-to-locked-funds

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

deposit-to-sdeusd:
	sui client call --package $(PACKAGE_ADDRESS) --module sdeusd --function deposit \
		--args \
			$(SDEUSD_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) \
			$(coins) $(receiver) 0x6

cooldown-sdeusd:
	sui client call --package $(PACKAGE_ADDRESS) --module sdeusd --function cooldown_shares \
		--args \
			$(SDEUSD_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) \
			$(coins) 0x6

set-cooldown-duration:
	sui client call --package $(PACKAGE_ADDRESS) --module sdeusd --function set_cooldown_duration \
		--args \
			$(ADMIN_CAP_ID) $(SDEUSD_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) \
			$(duration) 

convert-to-assets:
	sui client call --package $(PACKAGE_ADDRESS) --module sdeusd --function convert_to_assets \
		--args \
			$(SDEUSD_MANAGEMENT_ID) $(shares) false 0x6 --dev-inspect \

transfer-rewards:
	sui client call --package $(PACKAGE_ADDRESS) --module sdeusd --function transfer_in_rewards \
		--args \
			$(SDEUSD_MANAGEMENT_ID) $(GLOBAL_CONFIG_ID) \
			$(coins) 0x6

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

claim-deusd:
	sui client call --package $(PACKAGE_ADDRESS) --module wdeusd_vault --function claim_deusd \
		--type-args \
			$(WDEUSD_TYPE) \
		--args \
			$(WDEUSD_VAULT_ID) $(DEUSD_CONFIG_ID) $(wdeusd_coins) $(to)

return-deusd:
	sui client call --package $(PACKAGE_ADDRESS) --module wdeusd_vault --function return_deusd \
		--type-args \
			$(WDEUSD_TYPE) \
		--args \
			$(WDEUSD_VAULT_ID) $(DEUSD_CONFIG_ID) $(deusd_coins) $(to)

pause-wdeusd-vault:
	sui client call --package $(PACKAGE_ADDRESS) --module wdeusd_vault --function pause \
		--type-args \
			$(WDEUSD_TYPE) \
		--args \
			$(ADMIN_CAP_ID) $(WDEUSD_VAULT_ID)

unpause-wdeusd-vault:
	sui client call --package $(PACKAGE_ADDRESS) --module wdeusd_vault --function unpause \
		--type-args \
			$(WDEUSD_TYPE) \
		--args \
			$(ADMIN_CAP_ID) $(WDEUSD_VAULT_ID)