/********************************************************/
/*                                                      */
/* Parsing HTTP data                                    */
/*                                                      */
/* Author: Roberto Bonafiglia and Fulvio Risso          */
/*                                                      */
/* Note: this solution does not consider the case in    */
/* which HTTP data is split across multiple packets     */
/*                                                      */
/********************************************************/

// Standard C include file for I/O functions
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <inttypes.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

// Include files for libpcap functions
#include <pcap.h>

#define LINE_LEN 16

/* ethernet header */
typedef struct ether_header
{
    u_int8_t ether_dhost[6]; /* 6 bytes destination address */
    u_int8_t ether_shost[6]; /* 6 bytes source address */
    u_int16_t ether_type;	 /* 2 bytes ethertype */
} ether_header;

/* IPv4 header */
typedef struct ip_header
{
    u_int8_t ver_ihl;		  // Version (4 bits) + Internet header length (4 bits)
    u_int8_t tos;			  // Type of service
    u_int16_t tlen;			  // Total length
    u_int16_t identification; // Identification
    u_int16_t flags_fo;		  // Flags (3 bits) + Fragment offset (13 bits)
    u_int8_t ttl;			  // Time to live
    u_int8_t proto;			  // Protocol
    u_int16_t crc;			  // Header checksum
    u_int8_t ip_src[4];		  // Source address
    u_int8_t ip_dest[4];	  // Destination address
} ip_header;

/* TCP header*/
typedef struct tcp_header
{
    u_int16_t src_port;
    u_int16_t dest_port;
    u_int32_t seq_num;
    u_int32_t ack_num;
    u_int8_t data_offset_reserved;
    u_int8_t flags;
    u_int16_t window_size;
    u_int16_t checksum;
    u_int16_t urgent_pointer;
} tcp_header;

/* Prototype of the packet handler */
void packet_handler(u_char *param, const struct pcap_pkthdr *header, const u_char *pkt_data);

int main(int argc, char **argv)
{
    pcap_t *adhandle;
    char errbuf[PCAP_ERRBUF_SIZE];
    struct pcap_pkthdr *header;
    const u_char *pkt_data;
    u_int i = 0;
    int res;

    if (argc != 2)
    {
        printf("Usage: %s network_adapter_name \n\n", argv[0]);
        exit(EXIT_FAILURE);
    }

#ifdef __linux__
    if (geteuid() != 0)
    {
        fprintf(stderr, "Root permissions are required to run %s\n", argv[0]);
        exit(EXIT_FAILURE);
    }
#endif

    /* Open the capture file */
    if ((adhandle = pcap_open_live(argv[1], // name of the device to open
                                   BUFSIZ,
                                   1,	  // promiscuous mode
                                   1000,  // timeout in milliseconds
                                   errbuf // error buffer
                                   )) == NULL)
    {
        fprintf(stderr, "Unable to open the live capture on %s.\n\n", argv[1]);
        return -1;
    }

    /* start the capture */
    result = pcap_loop(adhandle, 0, packet_handler, NULL);
    if (result == -1) {
        printf("Error reading the packets: %s\n", pcap_geterr(adhandle));
    }

    pcap_close(adhandle);
    return 0;
}

/* Callback function invoked by libpcap for every incoming packet */
void packet_handler(u_char *param, const struct pcap_pkthdr *header, const u_char *pkt_data)
{
    time_t local_tv_sec;
    ip_header *ih;
    tcp_header *th;
    ether_header *eh;
    u_int16_t sport, dport;
    unsigned char *end, *payload, *host, *end_host, *complete_host;
    u_int32_t ip_header_len, tcp_header_len;

    /* Print timestamp and length of the packet */
    local_tv_sec = header->ts.tv_sec;
    fprintf(stdout, "%d.%06d ", (int)local_tv_sec, (int)header->ts.tv_usec);

    /* Cast the raw packet to the ether_header structure, in order to facilitate the parsing */
    eh = (ether_header *)pkt_data;

    fprintf(stdout, "%02X:%02X:%02X:%02X:%02X:%02X -> %02X:%02X:%02X:%02X:%02X:%02X   ",
            eh->ether_shost[0], eh->ether_shost[1], eh->ether_shost[2], eh->ether_shost[3], eh->ether_shost[4], eh->ether_shost[5],
            eh->ether_dhost[0], eh->ether_dhost[1], eh->ether_dhost[2], eh->ether_dhost[3], eh->ether_dhost[4], eh->ether_dhost[5]);

    /* Check if packet is IP */
    if (ntohs(eh->ether_type) != 0x0800)
    {
        /* This is not an IP packet. Just print Ethernet data */
        fprintf(stdout, "0.0.0.0 -> 0.0.0.0   0 0 -> 0\n");
        return;
    }

    /* Retrieve the position of the ip header */
    ih = (ip_header *)(pkt_data + 14); // length of ethernet header

    /* Check if the IP packet contains an UDP or TCP payload */
    /* No need for ntohx() here, as the field we are checking is a single byte only */
    fprintf(stdout, "%d.%d.%d.%d -> %d.%d.%d.%d   ",
            ih->ip_src[0], ih->ip_src[1], ih->ip_src[2], ih->ip_src[3],
            ih->ip_dest[0], ih->ip_dest[1], ih->ip_dest[2], ih->ip_dest[3]);

    switch (ih->proto)
    {
    case 0x01:
        fprintf(stdout, "ICMP 0 -> 0\n");
        return;
    case 0x02:
        fprintf(stdout, "IGMP 0 -> 0\n");
        return;
    case 0x2F:
        fprintf(stdout, "GRE 0 -> 0\n");
        return;
    case 0x32:
        fprintf(stdout, "ESP 0 -> 0\n");
        return;
    case 0x33:
        fprintf(stdout, "AH 0 -> 0\n");
        return;
    case 0x06:
        fprintf(stdout, "TCP ");
        break;
    case 0x11:
        fprintf(stdout, "UDP ");
        break;
    default:
        fprintf(stdout, "%d 0 -> 0\n", ih->proto);
        return;
    }

    /* NOTE: both TCP and UDP headers start with the PORT at the beginning of the packet. */
    /* Therefore we can use a trick here: we just cast the payload in a TCP header, then */
    /* we print the port number. This works also if the packet is UDP */

    /* Retrieve the position of the TCP/UDP header */
    ip_header_len = (ih->ver_ihl & 0xf) * 4;
    th = (tcp_header *)((u_char *)ih + ip_header_len);

    /* Convert from network byte order to host byte order */
    sport = ntohs(th->src_port);
    dport = ntohs(th->dest_port);

    fprintf(stdout, "%d -> %d", sport, dport);

    /* Retrieve the position of the TCP payload */
    tcp_header_len = (th->data_offset_reserved & 0xf0) >> 2; /* left shift of 4 positions, then *4 */
    payload = ((u_char *)th + tcp_header_len);
    /* Retrieve the pointer to the last byte of the packet */
    /* (to avoid buffer overflow later, when parsing the packet) */
    end = (unsigned char *)pkt_data + header->caplen;

    /* Extract HTTP data */
    // Check if the packet is the first packet of an HTTP request
    if ((ih->proto == 0x06 && dport == 80) &&
        ((strncmp(payload, "GET", 3) == 0) ||
         (strncmp(payload, "POST", 4) == 0) ||
         (strncmp(payload, "PUT", 3) == 0) ||
         (strncmp(payload, "DELETE", 6) == 0) ||
         (strncmp(payload, "HEAD", 4) == 0) ||
         (strncmp(payload, "TRACE", 5) == 0) ||
         (strncmp(payload, "OPTIONS", 7) == 0) ||
         (strncmp(payload, "CONNECT", 7) == 0)))
    {
        for (host = payload; *host != ' '; host++)
            ; // Search for the first space to find the end of the method

        *host = 0; // set the space after the method to 0 for the next print to print only the method

        fprintf(stdout, "   %s ", payload); // print the method - since *host is set to 0, in payload we have a string that terminates at the
                                            // host position
        host++;

        for (end_host = host; *end_host != ' ' && end_host < end; end_host++)
            ; // find the end of the resource until the first space

        *end_host = 0; // set the space after the resource to 0 for the next print to print only it
        end_host++;

        while (end_host < end - 5 && strncmp(end_host, "Host:", 5) != 0) // Search for the field Host on the header
        {
            for (; end_host < end && *end_host != '\r' && *(end_host + 1) != '\n'; end_host++)
                ; // each field terminates with \r\n

            if (*(end_host + 2) == '\r' && *(end_host + 3) == '\n')
                return;

            end_host += 2;
        }

        if (end_host < end - 5) // extract the data of the field host
        {
            end_host += 6;
            complete_host = end_host;

            for (; complete_host + 1 < end && *complete_host != '\r' && *(complete_host + 1) != '\n'; complete_host++)
                ; // each field terminates with \r\n

            *complete_host = 0;
        }

        fprintf(stdout, "%s%s\n", end_host, host); // print Host/resource
    }
    else
        fprintf(stdout, "\n");
}
