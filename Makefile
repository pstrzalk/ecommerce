CONTEXTS = $(shell find ecommerce -type d -maxdepth 1 -mindepth 1 -exec basename {} \;)

$(addprefix test-, $(CONTEXTS)):
	@make -C ecommerce/$(subst test-,,$@) test

test: $(addprefix test-, $(CONTEXTS)) ## Run all unit tests

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help