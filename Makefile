DOCKER ?= docker
JQ ?= jq
K0SCTL ?= k0sctl
K0S ?= k0s
KUBECTL ?= kubectl
SSH ?= ssh
TF ?= terraform

.PHONY: apply
apply: .tf.apply
.tf.apply: .terraform/.init $(shell find . -type f -name '*.tf') local.tfvars
	$(MAKE) -C alpine-image image.qcow2
	$(TF) apply -auto-approve -var-file=local.tfvars -var=k0sctl_path='$(K0SCTL)'
	touch -- '$@'

ssh.%: ID ?= 0
ssh.%: IP ?= $(shell $(TF) output -json $(patsubst .%,%,$(suffix $@))_infos | jq -r '.[$(ID)].ipv4')
.PHONY: ssh.controller
ssh.controller: .tf.apply
	@[ -n '$(IP)' ] || { echo No IP found.; echo '$(TF) refresh'; $(TF) refresh; exit 1; }
	$(SSH) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ./id_rsa 'k0s@$(IP)'

.PHONY: airgap-images.tar
airgap-images.tar:
	@set -e \
	  && set -- \
	  && images="$$($(K0S) airgap list-images)" \
	  && for image in $$images; do \
	    $(DOCKER) pull -- "$$image" \
	    && set -- "$$@" "$$image" \
	  ; done \
	  && echo Saving $@ ... \
	  && $(DOCKER) image save "$$@" -o '$@.tmp' \
	  && mv -- '$@.tmp' '$@'

.PHONY: destroy
destroy: .terraform/.init
	$(TF) destroy -auto-approve
	-rm terraform.tfstate terraform.tfstate.backup
	@#-rm kubeconfig .k0sctl.apply
	-rm .tf.apply

# This is now hackend into k0sctl.tf
# .PHONY: k0sctl.apply
# k0sctl.apply: .k0sctl.apply
# .k0sctl.apply: .tf.apply
# 	$(K0SCTL) apply --config=k0sctl.yaml
# 	$(K0SCTL) kubeconfig >kubeconfig
# 	touch -- '$@'

.PHONY: kube-env
kube-env:
	@echo '# use like so: eval "$$($(MAKE) $@)"'
	@echo export KUBECONFIG="'$(CURDIR)/kubeconfig'":'"$${KUBECONFIG-$$HOME/.kube/config}"'
	@echo echo KUBECONFIG set.

.terraform/.init: $(shell find . -type f -name 'terraform.tf')
	$(TF) init
	touch .terraform/.init

local.tfvars:
	@if [ ! -f '$@' ]; then \
	  { \
	    echo '# Put your variable overrides here ...' \
	    ; echo \
	    ; echo \
	    ; \
	  } >'$@' \
	  ; echo Put your local variable overrides into $@ \
	  ; \
	else \
	  touch -- '$@' \
	  ; \
	fi

clean:
	-$(MAKE) destroy
	-rm -rf .terraform
	-rm airgap-images.tar airgap-images.tar.tmp
	-$(MAKE) -C alpine-image clean
