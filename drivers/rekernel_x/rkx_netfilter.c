/*
 * Copyright (c) 2026 myflavor <admin@myflv.cn>. All rights reserved.
 * Based on Re-Kernel project by nep_timeline@outlook.com.
 * File: rkx_netfilter.c — Netfilter hooks & traffic metrics per UID.
 */

#include "rkx_log.h"
#include "rkx.h"
#include <linux/printk.h>
#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/netdevice.h>
#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/netfilter_ipv6.h>
#include <net/rtnetlink.h>
#include <net/sock.h>
#include <net/netfilter/nf_socket.h>
#include <net/ip.h>
#include <net/ipv6.h>
#include <net/tcp.h>
#include <linux/rcupdate.h>

/*
 * Parse TCP payload length from an IPv4 packet.
 * Returns 0 on success, -1 if the packet should be passed through.
 */
static int parse_tcp_ipv4(struct sk_buff *skb, __u8 *proto, int *data_len)
{
	struct iphdr *iph;
	unsigned int ip_hdr_len;
	struct tcphdr *th;

	if (!pskb_may_pull(skb, sizeof(struct iphdr)))
		return -1;

	iph = ip_hdr(skb);
	if (iph->version != 4 || iph->ihl < 5 ||
	    iph->protocol != IPPROTO_TCP || ip_is_fragment(iph))
		return -1;

	ip_hdr_len = iph->ihl << 2;
	if (!pskb_may_pull(skb, ip_hdr_len + sizeof(struct tcphdr)))
		return -1;

	iph = ip_hdr(skb);
	th = (struct tcphdr *)((unsigned char *)iph + ip_hdr_len);
	if (th->doff < 5 || ntohs(iph->tot_len) > skb->len ||
	    ntohs(iph->tot_len) < ip_hdr_len + (th->doff << 2))
		return -1;
	*data_len = ntohs(iph->tot_len) - ip_hdr_len - (th->doff << 2);

	if (*data_len <= 0 && !th->syn && !th->fin && !th->rst)
		return -1;

	*proto = RKX_NET_PROTO_IPV4;
	return 0;
}

#if IS_ENABLED(CONFIG_IPV6)
/*
 * Parse TCP payload length from an IPv6 packet.
 * Returns 0 on success, -1 if the packet should be passed through.
 */
static int parse_tcp_ipv6(struct sk_buff *skb, __u8 *proto, int *data_len)
{
	unsigned int thoff = 0;
	unsigned short frag_off = 0;
	struct ipv6hdr *iph6;
	struct tcphdr *th;

	if (!pskb_may_pull(skb, sizeof(struct ipv6hdr)))
		return -1;

	if (ipv6_find_hdr(skb, &thoff, -1, &frag_off, NULL) != IPPROTO_TCP ||
	    frag_off)
		return -1;

	if (!pskb_may_pull(skb, thoff + sizeof(struct tcphdr)))
		return -1;

	iph6 = ipv6_hdr(skb);
	th = (struct tcphdr *)(skb_network_header(skb) + thoff);
	if (iph6->version != 6 || th->doff < 5 ||
	    sizeof(*iph6) + ntohs(iph6->payload_len) > skb->len ||
	    sizeof(*iph6) + ntohs(iph6->payload_len) < thoff + (th->doff << 2))
		return -1;
	*data_len = ntohs(iph6->payload_len) - (thoff - sizeof(struct ipv6hdr))
	          - (th->doff << 2);

	if (*data_len <= 0 && !th->syn && !th->fin && !th->rst)
		return -1;

	*proto = RKX_NET_PROTO_IPV6;
	return 0;
}
#endif

static unsigned int rkx_pkg_ipv4_ipv6_in(void *priv, struct sk_buff *skb,
	const struct nf_hook_state *state)
{
	struct sock *sk;
	uid_t uid;
	int data_len;
	__u8 proto;

	if (!skb || !skb->len || !state)
		return NF_ACCEPT;

	if (state->hook != NF_INET_LOCAL_IN || !state->in)
		return NF_ACCEPT;

	/* LOCAL_IN has the network header at skb->data. Validate before lookup. */
	if (skb_network_offset(skb) != 0)
		return NF_ACCEPT;
	if (state->pf == NFPROTO_IPV4) {
		if (parse_tcp_ipv4(skb, &proto, &data_len) < 0)
			return NF_ACCEPT;
#if IS_ENABLED(CONFIG_IPV6)
	} else if (state->pf == NFPROTO_IPV6) {
		if (parse_tcp_ipv6(skb, &proto, &data_len) < 0)
			return NF_ACCEPT;
#endif
	} else {
		return NF_ACCEPT;
	}

	/*
	 * Early demux is an optimization, not a guarantee. Routed/redirected
	 * ingress can have no skb->sk; loopback can retain the sending socket.
	 * Resolve the receiving socket without stealing/changing skb ownership.
	 */
	sk = skb_to_full_sk(skb);
	if (!sk || !sk_fullsock(sk) || (state->in->flags & IFF_LOOPBACK)) {
		if (state->pf == NFPROTO_IPV4)
			sk = nf_sk_lookup_slow_v4(state->net, skb, state->in);
#if IS_ENABLED(CONFIG_IPV6)
		else
			sk = nf_sk_lookup_slow_v6(state->net, skb, state->in);
#endif
		if (!sk)
			return NF_ACCEPT;
		/* The lookup can return a time-wait/request socket: never read sk_uid. */
		uid = sk_fullsock(sk) ? __kuid_val(sk->sk_uid) : 0;
		sock_gen_put(sk);
	} else {
		uid = __kuid_val(sk->sk_uid);
	}
	if (uid < MIN_USERAPP_UID)
		return NF_ACCEPT;

	rcu_read_lock();
	if (!rkx_net_uid_monitored_rcu(uid)) {
		rcu_read_unlock();
		return NF_ACCEPT;
	}
	rcu_read_unlock();

	rkx_log_debug("Receive net data! target=%d\n", uid);
	if (rkx_netlink_ready()) {
		struct rkx_event event = {
			.type = RKX_EVT_NETWORK,
			.u.network = {
				.proto = proto,
				.target_uid = uid,
				.data_len = data_len,
			},
		};
		rkx_send_message(&event);
	}

	return NF_ACCEPT;
}

/* Only monitor input network packages */
static struct nf_hook_ops rkx_nf_ops[] = {
	{
		.hook     = rkx_pkg_ipv4_ipv6_in,
		.pf       = NFPROTO_IPV4,
		.hooknum  = NF_INET_LOCAL_IN,
		.priority = NF_IP_PRI_SELINUX_LAST + 1,
	},
#if IS_ENABLED(CONFIG_IPV6)
	{
		.hook     = rkx_pkg_ipv4_ipv6_in,
		.pf       = NFPROTO_IPV6,
		.hooknum  = NF_INET_LOCAL_IN,
		.priority = NF_IP6_PRI_SELINUX_LAST + 1,
	}
#endif
};

static bool netfilter_registered;

static void __unregister_netfilter(void)
{
	struct net *net;

	rtnl_lock();
	for_each_net(net) {
		nf_unregister_net_hooks(net, rkx_nf_ops, ARRAY_SIZE(rkx_nf_ops));
	}
	rtnl_unlock();
}

void rkx_unregister_netfilter(void)
{
	if (netfilter_registered) {
		__unregister_netfilter();
		netfilter_registered = false;
	}
}

int rkx_register_netfilter(void)
{
	int rc = LINE_SUCCESS;
	struct net *net = NULL;

	rtnl_lock();
	for_each_net(net) {
		rc = nf_register_net_hooks(net, rkx_nf_ops, ARRAY_SIZE(rkx_nf_ops));
		if (rc != LINE_SUCCESS) {
			rkx_log_err("register netfilter hooks failed, rc=%d\n", rc);
			break;
		}
	}
	rtnl_unlock();

	if (rc != LINE_SUCCESS) {
		__unregister_netfilter();
		return LINE_ERROR;
	}

	netfilter_registered = true;
	return LINE_SUCCESS;
}
