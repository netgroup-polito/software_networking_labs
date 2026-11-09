/* The statistics we are gonna collect for each l3 protocol and store in the
 * eBPF map
 */
struct l3proto_stats {
	unsigned long pkts;
	unsigned long bytes;
};