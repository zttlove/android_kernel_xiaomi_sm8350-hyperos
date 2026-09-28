rekernel_x-y := rkx.o rkx_genl.o rkx_netuid.o rkx_free_async.o rkx_frozen.o rkx_binder.o rkx_signal.o rkx_netfilter.o rkx_binder_kp.o rkx_binder_alloc.o

obj-$(CONFIG_REKERNEL_X) += rekernel_x.o

# Keep the in-tree build tied to the imported upstream release.  Builders can
# override this when updating the source: make RKX_VERSION=vX.Y.
RKX_VERSION ?= v1.6
ifdef RKX_VERSION
ccflags-y += -DRKX_VERSION=\"$(RKX_VERSION)\"
endif
