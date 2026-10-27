.PHONY: install uninstall

install:
	@source="$$(pwd -P)/icswebedit"; \
	destination="$${HOME:?HOME must be set}/.local/bin/icswebedit"; \
	if [ -e "$$destination" ] || [ -L "$$destination" ]; then \
		printf 'Already exists, skipping: %s\n' "$$destination"; \
		exit 0; \
	fi; \
	if [ ! -x "$$source" ]; then \
		printf 'Not executable: %s\n' "$$source" >&2; \
		exit 1; \
	fi; \
	mkdir -p "$$HOME/.local/bin" && ln -sn "$$source" "$$destination"

uninstall:
	@source="$$(pwd -P)/icswebedit"; \
	destination="$${HOME:?HOME must be set}/.local/bin/icswebedit"; \
	if [ -L "$$destination" ] && [ "$$(readlink "$$destination")" = "$$source" ]; then \
		rm "$$destination"; \
	elif [ -e "$$destination" ] || [ -L "$$destination" ]; then \
		printf 'Refusing to remove: %s\n' "$$destination" >&2; \
		exit 1; \
	fi
